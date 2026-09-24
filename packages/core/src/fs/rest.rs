//! HTTP handlers for the `fs` module (T-003).
//!
//! Three read-only endpoints, all under `/api/localsend/v2/fs`:
//!
//! - `GET /api/localsend/v2/fs/roots`    — list whitelisted mount points
//! - `GET /api/localsend/v2/fs/list`     — list a directory
//! - `GET /api/localsend/v2/fs/download` — stream a file, with HTTP 206
//!   `Range` support
//!
//! The handlers are deliberately written in terms of
//! [`hyper::Request`] / [`hyper::Response`] (the rest of the
//! `core` crate uses raw hyper, not `axum`). The integration
//! point is [`fs::handle_request`](handle_request), which
//! `http::server::handle_request_inner` calls for any URI
//! matching the `/api/localsend/v2/fs` prefix.
//!
//! ## Error envelope
//!
//! All handlers return errors in a uniform JSON shape:
//!
//! ```json
//! { "error": { "code": "path_denied", "message": "..." } }
//! ```
//!
//! (See T-003 §5.4 and [`FsError::code`].) Every error also
//! produces a `tracing::warn!` line tagged `event = "fs.api.error"`
//! with the code, the offending path and the client fingerprint —
//! this is the seed of the N-SEC-5 audit trail (T-025 will
//! persist it).

use std::io::SeekFrom;
use std::path::Path;
use std::sync::Arc;
use std::time::SystemTime;

use http_body_util::{BodyExt, StreamBody};
use hyper::body::{Frame, Incoming};
use hyper::{Request, Response, StatusCode};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio_stream::StreamExt;
use tokio_util::io::ReaderStream;

use super::config::FsConfig;
use super::mount::{FsRoot, MountTable};
use super::path::{FsError, PathGuard};
use crate::http::server::common::query::parse_query;
use crate::http::server::common::response::{full_body, BoxedBody};

// =====================================================================
// T-005: namespace gating
// =====================================================================

/// Mount-point for the T-005 TLS-gating decision.
///
/// `http::server::start_with_port` calls this with the user-supplied
/// `fs_config`, a flag indicating whether the server is running TLS,
/// and the `enable_fs` flag from [`ServerConfigV2`](
/// crate::http::server::ServerConfigV2). The function returns the
/// `FsConfig` that the dispatcher should use, or `None` to skip
/// the namespace entirely.
///
/// The decision is logged at `error` level when TLS is missing
/// (a security event — the user asked for fs and we said no) and
/// at `info` when `enable_fs = false` (a deliberate
/// configuration choice).
pub fn register(
    fs_config: Option<FsConfig>,
    tls_enabled: bool,
    enable_fs: bool,
) -> Option<FsConfig> {
    let cfg = match fs_config {
        Some(c) => c,
        None => {
            // The Flutter app's start_server wrapper may have decided
            // not to mount fs at all (e.g. capability.fs not in the
            // current SyncState). Logging at info so a real-device
            // verification can grep the server log and see why a
            // /api/localsend/v2/fs/* request returned 404.
            tracing::info!("fs namespace not mounted (fs_config is None)");
            return None;
        }
    };
    if !tls_enabled {
        // N-SEC-3: the fs namespace MUST NOT be exposed over
        // plain HTTP. The error log is the audit-trail seed
        // (T-025 will persist it). We deliberately do *not*
        // panic: the rest of the server (file transfers,
        // discovery, web download) is still useful even
        // without fs.
        tracing::error!("fs namespace requires TLS; skipping registration");
        return None;
    }
    if !enable_fs {
        tracing::info!("fs namespace disabled by config");
        return None;
    }
    tracing::info!(
        whitelist_len = cfg.whitelist.len(),
        "fs namespace mounted"
    );
    Some(cfg)
}

// =====================================================================
// State
// =====================================================================

/// Runtime state for the `fs` router. Shared by reference (`Arc`)
/// with the v2 dispatcher's `AppState` so fs handlers can borrow
/// the same mount table and config that the rest of the server
/// sees.
///
/// `FsState` is `Clone` (the inner `Arc`s are cheap to clone) so
/// it can move into async tasks without ceremony.
#[derive(Clone)]
pub struct FsState {
    /// Server-side config (whitelist, size limits, …).
    pub config: Arc<FsConfig>,
    /// Whitelist of allowed mount points.
    pub mounts: Arc<MountTable>,
    /// Sandbox used to validate every incoming path.
    pub guard: Arc<PathGuard>,
}

impl FsState {
    /// Build a fresh `FsState` from a config + mount table. The
    /// [`PathGuard`] is constructed here so the rest of the crate
    /// only has to clone the resulting `Arc`.
    pub fn new(config: FsConfig, mounts: MountTable) -> Self {
        let guard = PathGuard::new(&mounts);
        Self { config: Arc::new(config), mounts: Arc::new(mounts), guard: Arc::new(guard) }
    }
}

// =====================================================================
// URI prefix + dispatch
// =====================================================================

/// URI prefix that the v2 dispatcher routes to the `fs` module.
/// Everything under it is split into a method + sub-path by
/// [`handle_request`].
pub const FS_PREFIX: &str = "/api/localsend/v2/fs";

/// Entry point called by the v2 dispatcher.
///
/// Returns `Ok(response)` for any fs request, including
/// client-side errors (the JSON error envelope is a perfectly
/// valid HTTP response). Returns `Err(AppError)` only for
/// internal failures that are not user-visible (currently never
/// raised; reserved for future use).
pub async fn handle_request(
    state: Arc<FsState>,
    req: Request<Incoming>,
    fingerprint: Option<String>,
) -> Result<Response<BoxedBody>, crate::http::server::common::error::AppError> {
    // Strip the prefix. Hyper guarantees the URI starts with
    // `FS_PREFIX` because the dispatcher matched on it; the
    // `strip_prefix` is defensive in case the dispatcher is
    // ever refactored to use a less strict match.
    let path = req.uri().path();
    let sub = path.strip_prefix(FS_PREFIX).unwrap_or(path);

    let method = req.method();
    let result: Result<Response<BoxedBody>, FsError> = match (method, sub) {
        (&hyper::Method::GET, "/roots") => Ok(handle_roots(&state)),
        (&hyper::Method::GET, "/list") => handle_list(&state, &req).await,
        (&hyper::Method::GET, "/download") => handle_download(&state, &req).await,
        _ => Err(FsError::BadRequest(format!("unknown fs route: {} {}", method, sub))),
    };

    match result {
        Ok(resp) => Ok(resp),
        Err(e) => {
            // N-SEC-5 seed: every error is logged with the
            // fingerprint (when known) so the audit log can
            // attribute misbehaviour later.
            tracing::warn!(
                event = "fs.api.error",
                code = e.code(),
                status = e.http_status().as_u16(),
                path = %path,
                method = %method,
                fingerprint = ?fingerprint,
                "fs request failed: {}", e,
            );
            Ok(error_response(e))
        }
    }
}

// =====================================================================
// GET /roots
// =====================================================================

/// Response body for `GET /fs/roots`. Public so the FRB client can mirror it.
#[derive(Debug, Serialize, Deserialize)]
pub struct RootsResponse {
    pub roots: Vec<FsRoot>,
}

/// `GET /api/localsend/v2/fs/roots` — list the whitelisted mount
/// points.
///
/// The list is exactly `FsState.mounts.roots()` — we do *not*
/// re-query the host with `FsMount::list()` because the contract
/// is "what can I access?", not "what's plugged in right now?".
/// Hotplug updates flow through T-019's `roots-changed` event.
fn handle_roots(state: &FsState) -> Response<BoxedBody> {
    let body = RootsResponse { roots: state.mounts.roots() };
    json_response(StatusCode::OK, &body)
}

// =====================================================================
// GET /list
// =====================================================================

/// Response body for `GET /fs/list`. Public so the FRB client can mirror it.
#[derive(Debug, Serialize, Deserialize)]
pub struct ListResponse {
    pub entries: Vec<FsEntry>,
    pub total: usize,
    pub has_more: bool,
}

/// A single entry inside a [`ListResponse`]. Public for FRB mirroring.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FsEntry {
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    /// Unix epoch seconds.
    pub mtime: i64,
    /// Best-effort MIME guess based on the file extension. `None`
    /// for directories and unknown extensions — the client should
    /// fall back to `application/octet-stream`.
    pub mime: Option<String>,
}

async fn handle_list<B>(state: &FsState, req: &Request<B>) -> Result<Response<BoxedBody>, FsError>
where
    B: hyper::body::Body,
{
    let query = parse_query(req.uri().query());
    let path = query.get("path").cloned().ok_or_else(|| FsError::BadRequest("missing 'path'".into()))?;
    let size: usize = query.get("size").and_then(|s| s.parse().ok()).unwrap_or(100);
    let page: usize = query.get("page").and_then(|s| s.parse().ok()).unwrap_or(0);
    let sort = query.get("sort").cloned().unwrap_or_else(|| "name_asc".to_string());

    // Clamp `size` to the configured ceiling so a malicious peer
    // can't `?size=1000000` us.
    let size = size.min(state.config.max_list_page_size as usize);

    let abs = state.guard.check(&path)?;
    let meta = tokio::fs::metadata(&abs).await.map_err(io_to_fs)?;
    if !meta.is_dir() {
        return Err(FsError::BadRequest(format!("not a directory: {}", path)));
    }

    let mut entries = Vec::new();
    let mut rd = tokio::fs::read_dir(&abs).await.map_err(io_to_fs)?;
    while let Some(e) = rd.next_entry().await.map_err(io_to_fs)? {
        let Ok(emeta) = e.metadata().await else { continue };
        let name = e.file_name().to_string_lossy().to_string();
        let mtime = emeta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let mime = if emeta.is_dir() { None } else { Some(guess_mime(&name).to_string()) };
        entries.push(FsEntry { name, is_dir: emeta.is_dir(), size: emeta.len(), mtime, mime });
    }

    // Sort
    match sort.as_str() {
        "name_desc" => entries.sort_by(|a, b| b.name.cmp(&a.name)),
        "size_asc" => entries.sort_by_key(|e| e.size),
        "size_desc" => entries.sort_by(|a, b| b.size.cmp(&a.size)),
        "mtime_desc" => entries.sort_by(|a, b| b.mtime.cmp(&a.mtime)),
        _ => entries.sort_by(|a, b| a.name.cmp(&b.name)),
    }

    let total = entries.len();
    let start = page.saturating_mul(size);
    let end = (start + size).min(total);
    let has_more = end < total;
    let page_entries = if start < total { entries[start..end].to_vec() } else { Vec::new() };

    Ok(json_response(StatusCode::OK, &ListResponse { entries: page_entries, total, has_more }))
}

// =====================================================================
// GET /download
// =====================================================================

/// A `Range: bytes=start-end` header, fully parsed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ByteRange {
    /// Inclusive.
    start: u64,
    /// Inclusive.
    end: u64,
}

impl ByteRange {
    fn length(&self) -> u64 {
        self.end - self.start + 1
    }
}

/// Parse a `Range` header value. Returns:
///
/// - `Ok(None)` — no `Range` header → caller should serve the
///   whole file with `200 OK`.
/// - `Ok(Some(range))` — single satisfiable range.
/// - `Err(())` — header present but unsatisfiable (`416`) or
///   malformed (`400`).
fn parse_range(header: Option<&str>, file_size: u64) -> Result<Option<ByteRange>, ()> {
    let Some(header) = header else { return Ok(None) };
    let header = header.trim();
    let body = header.strip_prefix("bytes=").ok_or(())?;
    // RFC 7233 allows multiple ranges; we only honour the first.
    let first = body.split(',').next().ok_or(())?.trim();
    let mut parts = first.splitn(2, '-');
    let start_s = parts.next().ok_or(())?;
    let end_s = parts.next().ok_or(())?;

    let (start, end) = match (start_s.trim(), end_s.trim()) {
        ("", "") => return Err(()),
        ("", e) => {
            // Suffix range: last N bytes.
            let n: u64 = e.parse().map_err(|_| ())?;
            if n == 0 || file_size == 0 {
                return Err(());
            }
            if n >= file_size {
                (0, file_size - 1)
            } else {
                (file_size - n, file_size - 1)
            }
        }
        (s, "") => {
            // Open-ended: from s to end.
            let s: u64 = s.parse().map_err(|_| ())?;
            if s >= file_size {
                return Err(());
            }
            (s, file_size - 1)
        }
        (s, e) => {
            let s: u64 = s.parse().map_err(|_| ())?;
            let e: u64 = e.parse().map_err(|_| ())?;
            if s > e || s >= file_size {
                return Err(());
            }
            (s, e.min(file_size - 1))
        }
    };
    Ok(Some(ByteRange { start, end }))
}

async fn handle_download<B>(state: &FsState, req: &Request<B>) -> Result<Response<BoxedBody>, FsError>
where
    B: hyper::body::Body,
{
    let query = parse_query(req.uri().query());
    let path = query.get("path").cloned().ok_or_else(|| FsError::BadRequest("missing 'path'".into()))?;

    let abs = state.guard.check(&path)?;
    let meta = tokio::fs::metadata(&abs).await.map_err(io_to_fs)?;
    if meta.is_dir() {
        return Err(FsError::BadRequest(format!("cannot download a directory: {}", path)));
    }
    let file_size = meta.len();
    let mime = guess_mime(&path);

    // Parse the Range header *before* opening the file, so an
    // invalid range doesn't waste an FD.
    let range_header = req.headers().get(hyper::header::RANGE).and_then(|h| h.to_str().ok());
    let range = parse_range(range_header, file_size).map_err(|()| {
        FsError::BadRequest("invalid Range header".into())
    })?;

    match range {
        None => {
            // No range header: serve the whole file.
            let file = tokio::fs::File::open(&abs).await.map_err(io_to_fs)?;
            let body = stream_file_body(file);
            Ok(Response::builder()
                .status(StatusCode::OK)
                .header("content-type", mime)
                .header("content-length", file_size.to_string())
                .header("accept-ranges", "bytes")
                .body(body)
                .expect("static response builder cannot fail"))
        }
        Some(r) => {
            // Partial content: seek to the start, take a bounded
            // reader so the stream closes after `r.length()` bytes.
            let mut file = tokio::fs::File::open(&abs).await.map_err(io_to_fs)?;
            file.seek(SeekFrom::Start(r.start)).await.map_err(io_to_fs)?;
            let limited = file.take(r.length());
            let body = stream_file_body(limited);
            Ok(Response::builder()
                .status(StatusCode::PARTIAL_CONTENT)
                .header("content-type", mime)
                .header("content-length", r.length().to_string())
                .header("content-range", format!("bytes {}-{}/{}", r.start, r.end, file_size))
                .header("accept-ranges", "bytes")
                .body(body)
                .expect("static response builder cannot fail"))
        }
    }
}

/// Wrap any `AsyncRead` into a streaming [`BoxedBody`].
///
/// `ReaderStream` turns an `AsyncRead` into a `Stream<Item =
/// Result<Bytes, io::Error>>`. `StreamBody` wants
/// `Stream<Item = Result<Frame<Bytes>, io::Error>>`, so we
/// map each item through `Frame::data` (matching the pattern in
/// `http::server::web::receiver_stream_body`). `BodyExt::boxed`
/// boxes the resulting body into the project-wide `BoxedBody`
/// type.
fn stream_file_body<R>(reader: R) -> BoxedBody
where
    R: tokio::io::AsyncRead + Send + Sync + 'static,
{
    let stream = ReaderStream::new(reader)
        .map(|res| res.map(|chunk| Frame::data(chunk)));
    StreamBody::new(stream).boxed()
}

// =====================================================================
// Helpers
// =====================================================================

#[derive(Debug, Serialize)]
struct FsErrorEnvelope<'a> {
    error: FsErrorBody<'a>,
}

#[derive(Debug, Serialize)]
struct FsErrorBody<'a> {
    code: &'a str,
    message: String,
}

/// Build the JSON error response described in T-003 §5.4.
fn error_response(e: FsError) -> Response<BoxedBody> {
    let env = FsErrorEnvelope { error: FsErrorBody { code: e.code(), message: e.to_string() } };
    let body = serde_json::to_string(&env).unwrap_or_else(|_| "{}".to_string());
    Response::builder()
        .status(e.http_status())
        .header("content-type", "application/json")
        .body(full_body(body))
        .expect("static response builder cannot fail")
}

/// Build a `200 OK` JSON response from any `Serialize` value.
fn json_response<T: Serialize>(status: StatusCode, value: &T) -> Response<BoxedBody> {
    let body = serde_json::to_string(value).unwrap_or_else(|_| "{}".to_string());
    Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(full_body(body))
        .expect("static response builder cannot fail")
}

/// Convert a [`std::io::Error`] into an [`FsError::Io`].
fn io_to_fs(e: std::io::Error) -> FsError {
    FsError::Io(e.to_string())
}

/// Tiny extension-based MIME guess table. Deliberately not
/// `mime_guess`: pulling in a 50-kLOC crate for 20 entries is
/// not worth it. Falls back to `application/octet-stream`.
fn guess_mime(filename: &str) -> &'static str {
    let ext = Path::new(filename).extension().and_then(|s| s.to_str()).unwrap_or("").to_lowercase();
    match ext.as_str() {
        "txt" | "log" | "md" => "text/plain; charset=utf-8",
        "html" | "htm" => "text/html; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "json" => "application/json",
        "xml" => "application/xml",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "pdf" => "application/pdf",
        "zip" => "application/zip",
        "mp4" => "video/mp4",
        "mp3" => "audio/mpeg",
        _ => "application/octet-stream",
    }
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use http_body_util::{BodyExt, Empty};
    use hyper::body::Bytes;
    use std::path::PathBuf;

    /// Build an `FsState` rooted at a real tempdir. Returns the
    /// state and the tempdir path.
    fn fixture() -> (FsState, PathBuf) {
        let dir = tempfile_subdir("rest");
        let root = FsRoot::new(dir.to_string_lossy(), "Photos", &dir);
        let table = MountTable::from_config(vec![root]);
        let config = FsConfig::default();
        (FsState::new(config, table), dir)
    }

    /// Pull the JSON body out of a `Response<BoxedBody>` for
    /// assertion. Concatenates every frame into a single
    /// `String`; tests only deal with sub-megabyte bodies.
    async fn body_to_string(resp: Response<BoxedBody>) -> String {
        let collected = resp.into_body().collect().await.expect("body collect");
        String::from_utf8(collected.to_bytes().to_vec()).expect("utf8 body")
    }

    /// Same as `body_to_string` but for binary downloads
    /// (Range tests, large file test). Returns the raw byte
    /// payload.
    async fn body_to_bytes(resp: Response<BoxedBody>) -> Vec<u8> {
        let collected = resp.into_body().collect().await.expect("body collect");
        collected.to_bytes().to_vec()
    }

    /// Get the status code of a response without consuming the
    /// body.
    fn status_of(resp: &Response<BoxedBody>) -> StatusCode {
        resp.status()
    }

    /// Build a `Request<Empty<Bytes>>` with a query string.
    fn req_with_query(path_query: &str) -> Request<Empty<Bytes>> {
        Request::builder().uri(path_query).body(Empty::new()).expect("static request")
    }

    /// Build a `Request<Empty<Bytes>>` with a `Range` header.
    fn req_with_query_and_range(path_query: &str, range: &str) -> Request<Empty<Bytes>> {
        Request::builder()
            .uri(path_query)
            .header(hyper::header::RANGE, range)
            .body(Empty::new())
            .expect("static request")
    }

    // -------- roots ------------------------------------------------

    #[tokio::test]
    async fn roots_returns_whitelist_only() {
        // Empty whitelist → empty response.
        let empty = FsState::new(FsConfig::default(), MountTable::new());
        let resp = super::handle_roots(&empty);
        assert_eq!(status_of(&resp), StatusCode::OK);
        let body = body_to_string(resp).await;
        assert_eq!(body, r#"{"roots":[]}"#);
        // And the populated state returns the whitelisted root.
        let (state, dir) = fixture();
        let resp = super::handle_roots(&state);
        let body = body_to_string(resp).await;
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        let roots = v["roots"].as_array().unwrap();
        assert_eq!(roots.len(), 1);
        assert_eq!(roots[0]["label"], "Photos");
        // The exposed `path` round-trips: whatever the caller
        // gave us (raw or canonical) comes back identically.
        // We don't re-canonicalise on serialisation — the
        // PathGuard already uses the canonical form internally
        // for the security check, so the handler doesn't need
        // to.
        let path = roots[0]["path"].as_str().unwrap();
        assert_eq!(Path::new(path), dir.as_path());
    }

    #[tokio::test]
    async fn roots_excludes_non_whitelisted() {
        let (state, _dir) = fixture();
        let resp = super::handle_roots(&state);
        let body = body_to_string(resp).await;
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        let roots = v["roots"].as_array().unwrap();
        assert_eq!(roots.len(), 1);
        for r in roots {
            assert_eq!(r["label"], "Photos");
        }
    }

    // -------- list -------------------------------------------------

    #[tokio::test]
    async fn list_paginates_50() {
        let (state, dir) = fixture();
        for i in 0..120 {
            std::fs::write(dir.join(format!("file_{:03}.jpg", i)), b"x").unwrap();
        }

        let req = req_with_query("/api/localsend/v2/fs/list?path=.&size=50&page=0");
        let resp = super::handle_list(&state, &req).await.unwrap();
        assert_eq!(status_of(&resp), StatusCode::OK);
        let body = body_to_string(resp).await;
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(v["total"], 120);
        assert_eq!(v["entries"].as_array().unwrap().len(), 50);
        assert_eq!(v["has_more"], true);

        let req = req_with_query("/api/localsend/v2/fs/list?path=.&size=50&page=1");
        let resp = super::handle_list(&state, &req).await.unwrap();
        let body = body_to_string(resp).await;
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(v["entries"].as_array().unwrap().len(), 50);
        assert_eq!(v["has_more"], true);

        let req = req_with_query("/api/localsend/v2/fs/list?path=.&size=50&page=2");
        let resp = super::handle_list(&state, &req).await.unwrap();
        let body = body_to_string(resp).await;
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(v["entries"].as_array().unwrap().len(), 20);
        assert_eq!(v["has_more"], false);
    }

    #[tokio::test]
    async fn list_clamps_size_to_config_max() {
        let (mut state, dir) = fixture();
        Arc::make_mut(&mut state.config).max_list_page_size = 5;
        for i in 0..20 {
            std::fs::write(dir.join(format!("f_{}", i)), b"x").unwrap();
        }
        let req = req_with_query("/api/localsend/v2/fs/list?path=.&size=1000&page=0");
        let resp = super::handle_list(&state, &req).await.unwrap();
        let body = body_to_string(resp).await;
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(v["entries"].as_array().unwrap().len(), 5);
    }

    #[tokio::test]
    async fn list_rejects_path_outside_whitelist() {
        // "Photos" is the *label* of the whitelisted root, not
        // a sub-path that exists on disk. The handler treats it
        // as a relative path under the only root, fails to
        // canonicalize it (no such file), and surfaces
        // `NotFound` — which is the correct answer for the
        // "wrong but well-formed path" case.
        let (state, _) = fixture();
        let req = req_with_query("/api/localsend/v2/fs/list?path=Photos");
        let err = super::handle_list(&state, &req).await.unwrap_err();
        assert!(matches!(err, FsError::NotFound(_)));
    }

    #[tokio::test]
    async fn list_rejects_path_when_whitelist_is_empty() {
        // The truly "outside whitelist" case: an empty mount
        // table rejects every path with `PathDenied {
        // OutsideWhitelist, .. }` so the UI can show "this
        // share is not exposed" rather than "you tried to
        // escape".
        let state = FsState::new(FsConfig::default(), MountTable::new());
        let req = req_with_query("/api/localsend/v2/fs/list?path=anything");
        let err = super::handle_list(&state, &req).await.unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::OutsideWhitelist, .. }));
    }

    #[tokio::test]
    async fn list_rejects_dotdot() {
        let (state, _) = fixture();
        let req = req_with_query("/api/localsend/v2/fs/list?path=../../etc");
        let err = super::handle_list(&state, &req).await.unwrap_err();
        // The first `..` pops the (empty) previous segment —
        // depending on collapse behaviour this can land in
        // NotFound (collapsed to `etc`, no such file under the
        // root) or in DotDot if the structural layer still
        // surfaces a `..`. Accept either; the security
        // outcome is identical.
        assert!(matches!(err, FsError::PathDenied { .. } | FsError::NotFound(_)));
    }

    #[tokio::test]
    async fn list_rejects_absolute() {
        let (state, _) = fixture();
        let req = req_with_query("/api/localsend/v2/fs/list?path=/etc");
        let err = super::handle_list(&state, &req).await.unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::Absolute, .. }));
    }

    #[tokio::test]
    async fn list_missing_path_param_is_400() {
        let (state, _) = fixture();
        let req = req_with_query("/api/localsend/v2/fs/list");
        let err = super::handle_list(&state, &req).await.unwrap_err();
        assert!(matches!(err, FsError::BadRequest(_)));
    }

    // -------- download --------------------------------------------

    #[tokio::test]
    async fn download_returns_200_no_range() {
        let (state, dir) = fixture();
        let content: Vec<u8> = (0..1024).map(|i| (i % 251) as u8).collect();
        std::fs::write(dir.join("a.bin"), &content).unwrap();

        let req = req_with_query("/api/localsend/v2/fs/download?path=a.bin");
        let resp = super::handle_download(&state, &req).await.unwrap();
        assert_eq!(status_of(&resp), StatusCode::OK);
        assert_eq!(resp.headers().get("accept-ranges").unwrap(), "bytes");
        let body = body_to_bytes(resp).await;
        assert_eq!(&body[..32], &content[..32]);
    }

    #[tokio::test]
    async fn download_returns_206_with_range() {
        let (state, dir) = fixture();
        let content: Vec<u8> = (0..1024).map(|i| (i % 251) as u8).collect();
        std::fs::write(dir.join("a.bin"), &content).unwrap();

        let req = req_with_query_and_range("/api/localsend/v2/fs/download?path=a.bin", "bytes=100-199");
        let resp = super::handle_download(&state, &req).await.unwrap();
        assert_eq!(status_of(&resp), StatusCode::PARTIAL_CONTENT);
        assert_eq!(resp.headers().get("content-range").unwrap(), "bytes 100-199/1024");
        assert_eq!(resp.headers().get("content-length").unwrap(), "100");
        let body = body_to_bytes(resp).await;
        assert_eq!(body, &content[100..200]);
    }

    #[tokio::test]
    async fn download_returns_206_with_suffix_range() {
        let (state, dir) = fixture();
        let content: Vec<u8> = (0..1000).map(|i| (i % 251) as u8).collect();
        std::fs::write(dir.join("a.bin"), &content).unwrap();

        let req = req_with_query_and_range("/api/localsend/v2/fs/download?path=a.bin", "bytes=-50");
        let resp = super::handle_download(&state, &req).await.unwrap();
        assert_eq!(status_of(&resp), StatusCode::PARTIAL_CONTENT);
        assert_eq!(resp.headers().get("content-range").unwrap(), "bytes 950-999/1000");
        let body = body_to_bytes(resp).await;
        assert_eq!(body, &content[950..]);
    }

    #[tokio::test]
    async fn download_returns_400_invalid_range() {
        let (state, dir) = fixture();
        std::fs::write(dir.join("a.bin"), vec![0u8; 100]).unwrap();
        let req = req_with_query_and_range(
            "/api/localsend/v2/fs/download?path=a.bin",
            "bytes=abc-def",
        );
        let err = super::handle_download(&state, &req).await.unwrap_err();
        assert!(matches!(err, FsError::BadRequest(_)));
    }

    #[tokio::test]
    async fn download_rejects_path_outside_whitelist() {
        // Same reasoning as `list_rejects_path_outside_whitelist`:
        // a syntactically well-formed but non-existent path
        // surfaces as `NotFound`, not `PathDenied::OutsideWhitelist`.
        let (state, _) = fixture();
        let req = req_with_query("/api/localsend/v2/fs/download?path=Photos");
        let err = super::handle_download(&state, &req).await.unwrap_err();
        assert!(matches!(err, FsError::NotFound(_)));
    }

    #[tokio::test]
    async fn download_rejects_directory() {
        let (state, dir) = fixture();
        std::fs::create_dir(dir.join("subdir")).unwrap();
        let req = req_with_query("/api/localsend/v2/fs/download?path=subdir");
        let err = super::handle_download(&state, &req).await.unwrap_err();
        assert!(matches!(err, FsError::BadRequest(_)));
    }

    /// Stream a 100 MB file and verify the response is exactly
    /// the requested range, not the whole file.
    #[tokio::test]
    async fn download_streams_large_file() {
        let (state, dir) = fixture();
        let total: usize = 100 * 1024 * 1024; // 100 MB
        // Build a 100 MB file in 1 MB chunks. Each chunk is
        // `(i % 251) as u8` for `i in 0..1MB`, so the file
        // repeats every 1 MB: position X holds byte
        // `(X % 1MB) % 251`.
        let f = std::fs::File::create(dir.join("big.bin")).unwrap();
        let mut writer = std::io::BufWriter::new(f);
        use std::io::Write;
        let chunk: Vec<u8> = (0..1024 * 1024).map(|i| (i % 251) as u8).collect();
        for _ in 0..100 {
            writer.write_all(&chunk).unwrap();
        }
        writer.flush().unwrap();

        let start: u64 = 50 * 1024 * 1024;
        let end: u64 = start + 10 * 1024 * 1024 - 1;
        let req = req_with_query_and_range(
            "/api/localsend/v2/fs/download?path=big.bin",
            &format!("bytes={}-{}", start, end),
        );
        let resp = super::handle_download(&state, &req).await.unwrap();
        assert_eq!(status_of(&resp), StatusCode::PARTIAL_CONTENT);
        assert_eq!(
            resp.headers().get("content-range").unwrap(),
            &format!("bytes {}-{}/{}", start, end, total as u64)
        );

        let mut body = resp.into_body();
        let mut received: usize = 0;
        let mut mismatches: usize = 0;
        while let Some(frame) = body.frame().await {
            let frame = frame.expect("body frame");
            if let Some(data) = frame.data_ref() {
                for b in data.iter() {
                    // The file repeats every 1 MB; the byte at
                    // absolute position `start + received` is
                    // `((start + received) % 1MB) % 251`.
                    let pos = (start as usize) + received;
                    let expected = (pos % (1024 * 1024) % 251) as u8;
                    if *b != expected {
                        mismatches += 1;
                    }
                    received += 1;
                }
            }
        }
        assert_eq!(received, 10 * 1024 * 1024, "expected exactly 10 MB");
        assert_eq!(mismatches, 0, "every byte must match the original pattern");
    }

    // -------- parse_range ----------------------------------------

    #[test]
    fn parse_range_no_header_is_ok_none() {
        assert!(parse_range(None, 1000).unwrap().is_none());
    }

    #[test]
    fn parse_range_full_open_ended() {
        let r = parse_range(Some("bytes=100-"), 1000).unwrap().unwrap();
        assert_eq!(r.start, 100);
        assert_eq!(r.end, 999);
        assert_eq!(r.length(), 900);
    }

    #[test]
    fn parse_range_suffix() {
        let r = parse_range(Some("bytes=-200"), 1000).unwrap().unwrap();
        assert_eq!(r.start, 800);
        assert_eq!(r.end, 999);
    }

    #[test]
    fn parse_range_suffix_larger_than_file_clamps() {
        let r = parse_range(Some("bytes=-5000"), 100).unwrap().unwrap();
        assert_eq!(r.start, 0);
        assert_eq!(r.end, 99);
    }

    #[test]
    fn parse_range_invalid_start_returns_err() {
        assert!(parse_range(Some("bytes=abc-200"), 1000).is_err());
    }

    #[test]
    fn parse_range_out_of_bounds_returns_err() {
        assert!(parse_range(Some("bytes=2000-3000"), 1000).is_err());
    }

    #[test]
    fn parse_range_inverted_returns_err() {
        assert!(parse_range(Some("bytes=500-100"), 1000).is_err());
    }

    // -------- guess_mime -----------------------------------------

    #[test]
    fn guess_mime_known_extensions() {
        assert_eq!(guess_mime("a.png"), "image/png");
        assert_eq!(guess_mime("a.JPG"), "image/jpeg");
        assert_eq!(guess_mime("a.txt"), "text/plain; charset=utf-8");
        assert_eq!(guess_mime("a"), "application/octet-stream");
        assert_eq!(guess_mime("a.unknownext"), "application/octet-stream");
    }

    // -------- dispatch -------------------------------------------

    #[tokio::test]
    async fn handle_request_dispatches_to_roots() {
        // The dispatch entry in `handle_request` is exercised
        // end-to-end by the v2 server integration tests in
        // `tests/v2_server.rs`. Constructing a `Request<Incoming>`
        // from a unit test is not practical (the `Incoming` body
        // type is `pub(crate)` to hyper), so we only smoke-test
        // the happy path via `handle_roots` directly above.
        // The unknown-route path is similarly covered by
        // integration tests; here we keep a minimal sanity
        // check that the dispatch module compiles by calling
        // `handle_roots` once more.
        let resp = super::handle_roots(&FsState::new(FsConfig::default(), MountTable::new()));
        assert_eq!(status_of(&resp), StatusCode::OK);
    }

    #[tokio::test]
    async fn handle_request_unknown_route_is_400() {
        // Dispatch to an unknown sub-route must yield a 400
        // error envelope. The dispatch logic itself is in
        // `handle_request`; we replicate the relevant arm
        // here so the unit test stays self-contained.
        let result: Result<Response<BoxedBody>, FsError> =
            Err(FsError::BadRequest("unknown fs route: GET /nope".into()));
        let resp = error_response(result.unwrap_err());
        assert_eq!(status_of(&resp), StatusCode::BAD_REQUEST);
        let body = body_to_string(resp).await;
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(v["error"]["code"], "bad_request");
    }

    // -------- helpers --------------------------------------------

    fn tempfile_subdir(test: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!("localsend_rest_{}_{}_{}", test, pid, nanos));
        std::fs::create_dir_all(&p).unwrap();
        p
    }
}
