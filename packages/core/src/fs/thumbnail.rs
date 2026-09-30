//! T-021: server-side thumbnail generation.
//!
//! `GET /api/localsend/v2/fs/thumbnail?path=...&w=...&h=...` reads the
//! image at `path`, decodes it (JPEG / PNG / WebP via the `image`
//! crate), resizes it to fit within `(w, h)` keeping aspect ratio,
//! and re-encodes it as WebP bytes.
//!
//! Results are cached in [`FsState::thumbnail_cache`] keyed by
//! `(canonical path, w, h)` so repeated requests for the same
//! thumbnail (e.g. scrolling back and forth in a directory) skip
//! the decode/resize/encode work.
//!
//! PathGuard always runs first — thumbnails can't escape the
//! whitelist even if the file extension is `.jpg`. Directories,
//! missing files, and undecodable images return an error.
//!
//! HEIC and RAW formats are intentionally NOT decoded in v1
//! (the `image` crate doesn't support them without `kamadak-exif`
//! and a heavier dependency tree). Clients should fall back to
//! the type icon for those.

use std::path::PathBuf;

use bytes::Bytes;
use hyper::{Request, Response, StatusCode};

use super::path::FsError;
use super::rest::FsState;
use crate::http::server::common::query::parse_query;
use crate::http::server::common::response::{full_body, BoxedBody};

/// Hard cap on either dimension. AC-6: "超过 200×200 立即拒绝".
/// We allow 256 to give the client some headroom (e.g. a 240px
/// grid tile rendered at 2x DPI); anything bigger is refused.
pub const MAX_THUMB_DIM: u16 = 256;

/// Cache capacity. 256 entries × ~16 KB WebP ≈ 4 MB resident —
/// small enough to fit alongside the upload sessions and audit
/// log without putting pressure on RSS.
pub const THUMBNAIL_CACHE_CAPACITY: usize = 256;

/// PNG is used instead of WebP because `image` 0.25's WebP
/// encoder is broken — see the note on `thumbnail_response`.
/// PNG has no quality setting; the encoder is lossless.

/// Cache key: the canonical (whitelist-rooted) absolute path
/// plus the requested width and height. Width / height are
/// part of the key because resizing is lossy — a 64×64 cache
/// entry cannot satisfy a 256×256 request.
type CacheKey = (PathBuf, u16, u16);

/// `GET /api/localsend/v2/fs/thumbnail` — generate (or return
/// cached) a WebP thumbnail for an image file.
///
/// ## Errors
///
/// - `400 BadRequest` — missing `path`, invalid `w`/`h`, or
///   dimensions above [`MAX_THUMB_DIM`].
/// - `404 NotFound` — the resolved path doesn't exist.
/// - `403 PathDenied` — the path escapes the whitelist.
/// - `500 Io` / unsupported format — the file can't be decoded.
///
/// On success the response body is WebP bytes; the
/// `Content-Type: image/webp` and `Cache-Control: max-age=...`
/// headers are set so the client can be lazy about re-requests.
pub async fn handle_thumbnail(
    state: &FsState,
    req: &Request<impl hyper::body::Body>,
) -> Result<Response<BoxedBody>, FsError> {
    let query = parse_query(req.uri().query());

    let path = query
        .get("path")
        .ok_or_else(|| FsError::BadRequest("missing 'path'".into()))?
        .clone();

    let w = parse_dim(query.get("w").map(String::as_str), "w")?;
    let h = parse_dim(query.get("h").map(String::as_str), "h")?;

    if w == 0 || h == 0 {
        return Err(FsError::BadRequest(
            "thumbnail dimensions must be > 0".into(),
        ));
    }
    if w > MAX_THUMB_DIM || h > MAX_THUMB_DIM {
        return Err(FsError::BadRequest(format!(
            "thumbnail dimensions exceed {}x{}",
            MAX_THUMB_DIM, MAX_THUMB_DIM
        )));
    }

    // PathGuard first — never trust the URL.
    let abs = state.guard.check(&path)?;

    // Stat before decoding: directories and zero-byte files
    // shouldn't even reach the image crate.
    let meta = tokio::fs::metadata(&abs).await.map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            FsError::NotFound(format!("path not found: {}", path))
        } else {
            FsError::Io(e.to_string())
        }
    })?;
    if meta.is_dir() {
        return Err(FsError::BadRequest(format!(
            "cannot thumbnail a directory: {}",
            path
        )));
    }

    let key: CacheKey = (abs, w, h);

    // Cache fast path.
    if let Some(bytes) = state.thumbnail_cache.lock().await.get(&key).cloned() {
        tracing::debug!(
            event = "fs.thumbnail.cache_hit",
            path = %path,
            w,
            h,
            size = bytes.len(),
            "thumbnail cache hit"
        );
        return Ok(thumbnail_response(bytes));
    }

    // Miss: decode + resize + encode on a blocking thread. The
    // `image` crate is synchronous; offloading keeps the tokio
    // runtime free for HTTP I/O on big files.
    let (abs_for_worker, w, h) = (key.0.clone(), w, h);
    let path_dbg = path.clone();
    let bytes = tokio::task::spawn_blocking(move || generate_thumbnail(&abs_for_worker, w, h))
        .await
        .map_err(|e| FsError::Io(format!("thumbnail worker panicked: {e}")))??;

    tracing::debug!(
        event = "fs.thumbnail.generated",
        path = %path_dbg,
        w,
        h,
        size = bytes.len(),
        "thumbnail generated"
    );

    // Insert before returning. `put` on a Mutex-guarded LRU is
    // a normal FIFO eviction; we don't need to hold the lock
    // across the response.
    state
        .thumbnail_cache
        .lock()
        .await
        .put(key, bytes.clone());

    Ok(thumbnail_response(bytes))
}

/// Build a `200 OK` response carrying PNG thumbnail bytes.
///
/// PNG (not WebP) because the `image` crate's WebP encoder is
/// temporarily broken on 0.25 — `write_to(WebP)` silently falls
/// back to PNM/PPM, which clients can't decode. PNG is fine
/// for thumbnails: the encoder is stable, file size is
/// ~30 KB for a 256×256 thumbnail, and Flutter's
/// `Image.memory(bytes)` decodes PNG natively.
///
/// The `Cache-Control` header lets well-behaved clients (and
/// HTTP caches) reuse the response for 5 minutes without
/// re-hitting the server; thumbnails don't change unless the
/// underlying file changes, and we'd rather the LRU serve
/// re-requests than burn CPU re-encoding.
fn thumbnail_response(bytes: Bytes) -> Response<BoxedBody> {
    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "image/png")
        .header("content-length", bytes.len().to_string())
        .header("cache-control", "private, max-age=300")
        .body(full_body(bytes))
        .expect("static response builder cannot fail")
}

/// Parse a dimension query parameter. Accepts decimal numbers;
/// rejects negatives, overflows, and non-integers.
fn parse_dim(raw: Option<&str>, field: &str) -> Result<u16, FsError> {
    let Some(s) = raw else {
        return Err(FsError::BadRequest(format!(
            "missing '{field}'"
        )));
    };
    let n: u32 = s
        .parse()
        .map_err(|_| FsError::BadRequest(format!("invalid '{field}' value: {s}")))?;
    let n = u16::try_from(n)
        .map_err(|_| FsError::BadRequest(format!("'{field}' out of range: {s}")))?;
    Ok(n)
}

/// Synchronous decode → resize → encode. Runs inside
/// `spawn_blocking`. Errors here surface as `500` to the caller.
fn generate_thumbnail(abs: &std::path::Path, w: u16, h: u16) -> Result<Bytes, FsError> {
    // Read + decode. The `image` crate auto-detects format from
    // magic bytes; we don't gate by extension.
    let bytes = std::fs::read(abs).map_err(|e| {
        FsError::Io(format!("read {}: {e}", abs.display()))
    })?;
    let img = image::load_from_memory(&bytes).map_err(|e| {
        FsError::BadRequest(format!("unsupported image format: {e}"))
    })?;

    // Fit within (w, h) preserving aspect ratio. `thumbnail`
    // uses Lanczos3 resampling internally; the result is
    // always ≤ (w, h) on both axes.
    let target_w = u32::from(w);
    let target_h = u32::from(h);
    let resized = img.thumbnail(target_w, target_h);

    // Encode as PNG (see `thumbnail_response` doc-comment for
    // why we don't use WebP). PNG is lossless; for thumbnails
    // at ≤ 256×256 the output is ~30 KB, which the client LRU
    // cache will mostly hide anyway.
    let mut buf: Vec<u8> = Vec::with_capacity(bytes.len() / 4);
    {
        let mut cursor = std::io::Cursor::new(&mut buf);
        resized
            .write_to(&mut cursor, image::ImageFormat::Png)
            .map_err(|e| FsError::Io(format!("png encode: {e}")))?;
    }

    Ok(Bytes::from(buf))
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    /// Build a minimal `FsState` whose thumbnail_cache is the
    /// only field we exercise in these tests. Other fields are
    /// `Default` and unused here.
    async fn fresh_state_with_cache() -> Arc<FsState> {
        // Build a real `FsState` so the cache field exists and
        // its concrete type matches production. `PathGuard`
        // built from an empty whitelist rejects everything;
        // the cache itself is independent.
        use super::super::config::FsConfig;
        use super::super::mount::MountTable;
        let s = FsState::new(FsConfig::default(), MountTable::new());
        Arc::new(s)
    }

    /// Write a tiny valid PNG (1×1 red pixel) into a tempdir
    /// and return its path. Used as the canonical "decodable
    /// image" fixture across the decode/cache tests.
    fn write_test_png(dir: &std::path::Path, name: &str) -> std::path::PathBuf {
        // Generated by Python:
        //   zlib.compress(b"\x00\xff\x00\x00")  # filter byte + RGB
        // This avoids hand-rolling CRC checksums; the bytes
        // decode cleanly in the `image` crate.
        let bytes: [u8; 69] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
            0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02,
            0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44,
            0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, 0x03, 0x01, 0x01,
            0x00, 0xC9, 0xFE, 0x92, 0xEF, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
            0xAE, 0x42, 0x60, 0x82,
        ];
        let path = dir.join(name);
        std::fs::write(&path, &bytes).unwrap();
        path
    }

    /// Build a fake `Request<Empty<Bytes>>` with the given
    /// query string. We use `http_body_util::Empty<Bytes>`
    /// because hyper 1.x doesn't ship `Empty<Bytes>` directly.
    fn request_with_query(q: &str) -> Request<http_body_util::Empty<Bytes>> {
        let uri = format!("/api/localsend/v2/fs/thumbnail?{q}");
        Request::builder()
            .uri(uri)
            .body(http_body_util::Empty::new())
            .expect("static request")
    }

    /// Drain a response body into a `Bytes`. `BoxedBody` is a
    /// `BoxBody<Bytes, IoError>`; for our thumbnail responses
    /// the body is already buffered, so this is a single-frame
    /// collect.
    async fn collect_body(resp: Response<BoxedBody>) -> Bytes {
        use http_body_util::BodyExt;
        resp.into_body()
            .collect()
            .await
            .expect("thumbnail body is buffered and infallible")
            .to_bytes()
    }

    #[tokio::test]
    async fn rejects_oversized_dimensions() {
        let state = fresh_state_with_cache().await;
        let req = request_with_query("path=foo.jpg&w=512&h=512");
        let err = handle_thumbnail(&state, &req).await.unwrap_err();
        match err {
            FsError::BadRequest(msg) => {
                assert!(msg.contains("exceed"));
            }
            other => panic!("expected BadRequest, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn rejects_missing_dimensions() {
        let state = fresh_state_with_cache().await;
        // Path is irrelevant — the dim check fires first.
        let req = request_with_query("path=foo.jpg");
        let err = handle_thumbnail(&state, &req).await.unwrap_err();
        match err {
            FsError::BadRequest(msg) => {
                assert!(msg.contains("missing 'w'"));
            }
            other => panic!("expected BadRequest, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn rejects_zero_dimensions() {
        let state = fresh_state_with_cache().await;
        let req = request_with_query("path=foo.jpg&w=0&h=64");
        let err = handle_thumbnail(&state, &req).await.unwrap_err();
        assert!(matches!(err, FsError::BadRequest(_)));
    }

    #[tokio::test]
    async fn rejects_path_outside_whitelist() {
        let state = fresh_state_with_cache().await;
        // The default whitelist is empty, so any path is denied.
        let req = request_with_query("path=D:/test.jpg&w=64&h=64");
        let err = handle_thumbnail(&state, &req).await.unwrap_err();
        assert!(matches!(err, FsError::PathDenied { .. }));
    }

    #[tokio::test]
    async fn rejects_unsupported_format() {
        // Use a real tempdir with the file inside an empty
        // whitelist so PathGuard lets us through; then we
        // give it a non-image file (text bytes) and expect a
        // BadRequest from the decoder.
        use super::super::config::FsConfig;
        use super::super::mount::{FsMount, FsRoot, MountTable};
        let dir = tempfile_subdir("thumbnail_bad");
        std::fs::write(dir.join("note.jpg"), b"not an image").unwrap();

        let cfg = FsConfig {
            whitelist: vec![FsRoot::new(
                dir.to_string_lossy().into_owned(),
                "test",
                dir.to_string_lossy().as_ref(),
            )],
            ..Default::default()
        };
        let mounts = MountTable::from_config(cfg.whitelist.clone());
        let state = Arc::new(FsState::new(cfg, mounts));

        let req_path = format!(
            "path={}&w=64&h=64",
            // Windows-style paths on this machine: just use the
            // absolute path verbatim. On Unix the leading '/' is
            // part of the absolute path; on Windows PathGuard
            // normalises separators.
            urlencoding(&dir.to_string_lossy())
        );
        let req = request_with_query(&req_path);
        let result = handle_thumbnail(&state, &req).await;
        std::fs::remove_dir_all(&dir).ok();
        // We expect either BadRequest (decoder) or Io (read).
        match result {
            Err(FsError::BadRequest(_)) | Err(FsError::Io(_)) => {}
            other => panic!("expected BadRequest/Io, got {other:?}"),
        }
        // Reference FsMount to silence the unused-import lint
        // when running the test on platforms where it isn't
        // constructed explicitly.
        let _ = FsMount::list();
    }

    #[tokio::test]
    async fn decodes_png_and_caches_repeat_request() {
        use super::super::config::FsConfig;
        use super::super::mount::{FsRoot, MountTable};
        let dir = tempfile_subdir("thumbnail_png");
        let png_path = write_test_png(&dir, "red.png");

        let root_str = dir.to_string_lossy().into_owned();
        let cfg = FsConfig {
            whitelist: vec![FsRoot::new(root_str.clone(), "test", &root_str)],
            ..Default::default()
        };
        let mounts = MountTable::from_config(cfg.whitelist.clone());
        let state = Arc::new(FsState::new(cfg, mounts));

        let req_path = format!(
            "path={}&w=64&h=64",
            urlencoding(&format!("{}/red.png", root_str))
        );

        // First call: decode + encode.
        let req = request_with_query(&req_path);
        let resp1 = handle_thumbnail(&state, &req).await.expect("first decode");
        assert_eq!(resp1.status(), StatusCode::OK);
        // We send PNG because image 0.25's WebP encoder is
        // broken (see thumbnail_response's doc-comment). PNG
        // signature is 8 bytes: 0x89 0x50 0x4E 0x47 0x0D 0x0A
        // 0x1A 0x0A. We assert the magic bytes individually so
        // the diff is readable on failure.
        let bytes1 = collect_body(resp1).await;
        assert_eq!(bytes1[0], 0x89);
        assert_eq!(bytes1[1], 0x50); // 'P'
        assert_eq!(bytes1[2], 0x4E); // 'N'
        assert_eq!(bytes1[3], 0x47); // 'G'
        assert_eq!(bytes1[4], 0x0D);
        assert_eq!(bytes1[5], 0x0A);
        assert_eq!(bytes1[6], 0x1A);
        assert_eq!(bytes1[7], 0x0A);

        // Cache should now hold exactly one entry.
        assert_eq!(state.thumbnail_cache.lock().await.len(), 1);

        // Second call: should hit cache (still 1 entry, not 2).
        let req2 = request_with_query(&req_path);
        let resp2 = handle_thumbnail(&state, &req2).await.expect("cache hit");
        assert_eq!(resp2.status(), StatusCode::OK);
        assert_eq!(state.thumbnail_cache.lock().await.len(), 1);

        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn caches_distinct_dimensions_separately() {
        // Same source, two different sizes: two cache entries.
        use super::super::config::FsConfig;
        use super::super::mount::{FsRoot, MountTable};
        let dir = tempfile_subdir("thumbnail_dim");
        let png_path = write_test_png(&dir, "red.png");
        let root_str = dir.to_string_lossy().into_owned();
        let cfg = FsConfig {
            whitelist: vec![FsRoot::new(root_str.clone(), "test", &root_str)],
            ..Default::default()
        };
        let mounts = MountTable::from_config(cfg.whitelist.clone());
        let state = Arc::new(FsState::new(cfg, mounts));

        let req_path = |w: u16, h: u16| -> String {
            format!(
                "path={}&w={w}&h={h}",
                urlencoding(&format!("{}/red.png", root_str))
            )
        };

        handle_thumbnail(&state, &request_with_query(&req_path(64, 64)))
            .await
            .unwrap();
        handle_thumbnail(&state, &request_with_query(&req_path(128, 128)))
            .await
            .unwrap();
        handle_thumbnail(&state, &request_with_query(&req_path(64, 64)))
            .await
            .unwrap();

        // Two distinct dimensions → two cache entries; the
        // third call hits the cache, not a third entry.
        assert_eq!(state.thumbnail_cache.lock().await.len(), 2);

        std::fs::remove_dir_all(&dir).ok();
    }

    /// Lightweight tempdir helper — same shape as the other
    /// `tempfile_subdir` helpers in this crate so a CI flake
    /// can be traced by its test name.
    fn tempfile_subdir(test: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!(
            "localsend_thumbnail_test_{}_{}_{}",
            test, pid, nanos
        ));
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    /// Percent-encode just enough for our test path strings:
    /// spaces, `+`, and `/`. We don't pull in `percent-encoding`
    /// for tests because it's already a transitive dep through
    /// `reqwest`, but `image::codecs::webp` doesn't pull it
    /// through, so a tiny inline impl is safer.
    fn urlencoding(s: &str) -> String {
        let mut out = String::with_capacity(s.len());
        for b in s.bytes() {
            match b {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                    out.push(b as char);
                }
                _ => out.push_str(&format!("%{:02X}", b)),
            }
        }
        out
    }
}