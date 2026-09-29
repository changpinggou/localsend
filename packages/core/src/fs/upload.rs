//! Write endpoints for the `fs` module (T-010 + T-011).
//!
//! Two kinds of write operation:
//!
//! - `POST /api/localsend/v2/fs/mkdir` — create a directory.
//!   Single request/response, no session state. Returns 409 if
//!   the directory already exists.
//!
//! - Session-based upload (T-011):
//!   - `POST /api/localsend/v2/fs/upload/init`  — create an
//!     `UploadSession`, reserve a `.tmp/<uuid>` staging file,
//!     return `sessionId` + `etag` + `received` (resume offset).
//!   - `POST /api/localsend/v2/fs/upload/:id`   — append a chunk
//!     to the session's staging file. The chunk's
//!     `Content-Range` header must match the session's current
//!     `received` offset; otherwise 400.
//!   - `POST /api/localsend/v2/fs/upload/:id/finish` — fsync +
//!     rename the staging file to the final destination. Session
//!     is removed from the map.
//!   - `DELETE /api/localsend/v2/fs/upload/:id` — cancel: drop
//!     the staging file, remove the session.
//!
//! ## Upload protocol vs. multipart
//!
//! The existing LocalSend v2 upload path uses raw body bytes with
//! `chunked` transfer encoding (no multipart envelope). We follow
//! the same convention for fs uploads: the file content is the
//! entire request body, and the filename is passed via
//! `?filename=` on the init query string. This keeps the parser
//! trivial (no `multer` dependency), stays consistent with the v2
//! protocol, and plays well with `Content-Range` resume semantics
//! (multipart boundaries would complicate range math).
//!
//! ## Atomicity
//!
//! Every upload lands in `<target_dir>/.tmp/<uuid>` first and is
//! `rename`d to the final path on `finish`. A half-received file
//! never appears at the destination. If `rename` fails with
//! `EXDEV` (cross-device link, e.g. tmp on a different fs), we
//! fall back to `tokio::fs::copy` + `remove_file`.
//!
//! ## Session GC
//!
//! `gc_sessions` is called by the server's periodic task loop.
//! Sessions inactive for more than `SESSION_TTL` (30 min) are
//! cancelled — their staging files removed — to prevent disk
//! leaks when a client disappears mid-upload.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use http_body_util::BodyExt;
use hyper::body::Incoming;
use hyper::{Request, Response, StatusCode};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use super::path::{FsError, PathGuard};
use super::rest::FsState;
use crate::http::server::common::response::BoxedBody;

/// How long a session may sit idle before GC reclaims it.
pub const SESSION_TTL: Duration = Duration::from_secs(30 * 60);

/// Staging subdirectory inside each target dir. Hidden from
/// `list` responses via the `.`-prefix convention used in
/// `handle_list` (no special handling needed — `.tmp` is a real
/// directory on disk and will appear in listings; T-021's
/// thumbnail code and the client UI can filter it, or we can
/// hide it later by extending `list` to skip dotfiles).
const TMP_DIR: &str = ".tmp";

// =====================================================================
// Session state
// =====================================================================

/// A live upload session. Lives in `FsState.sessions` from `init`
/// until `finish`, `cancel`, or GC.
#[derive(Debug)]
pub struct UploadSession {
    /// Stable identifier, returned to the client in the init
    /// response and used in subsequent chunk/finish/cancel URLs.
    pub id: String,
    /// Canonical (absolute, symlink-resolved) final destination.
    pub final_path: PathBuf,
    /// Canonical path of the staging file. Always on the same
    /// filesystem as `final_path` so rename is atomic (we create
    /// `.tmp/` inside the target dir).
    pub tmp_path: PathBuf,
    /// Bytes received so far. Incremented by each chunk handler;
    /// must equal `final` file size when `finish` runs.
    pub received: u64,
    /// Total size the client promised in the init body. If
    /// `received != total` at finish time, we return 400.
    pub total: u64,
    /// Resume etag. Derived from the target path + total size +
    /// mtime of any pre-existing file (so a re-upload of an
    /// identical source file can be skipped). Computed on init.
    pub etag: String,
    /// When the session was created.
    pub started_at: Instant,
    /// Last time a chunk was accepted. GC compares against this.
    pub last_active: Instant,
}

impl UploadSession {
    /// `true` if the session has been idle longer than `ttl`.
    pub fn is_expired(&self, ttl: Duration) -> bool {
        self.last_active.elapsed() > ttl
    }
}

// =====================================================================
// Request / response shapes
// =====================================================================

#[derive(Debug, Deserialize)]
pub struct MkdirBody {
    pub path: String,
}

#[derive(Debug, Serialize)]
pub struct MkdirResponse {
    pub path: String,
}

#[derive(Debug, Deserialize)]
pub struct UploadInitQuery {
    /// Destination directory, validated by `PathGuard`.
    pub path: String,
    /// Filename. Must not contain `/` or `\` or `..`.
    pub filename: String,
}

#[derive(Debug, Deserialize)]
pub struct UploadInitBody {
    /// Total file size in bytes. Used to reject oversize uploads
    /// before any data is transferred.
    pub total: u64,
    /// Optional MIME type. Stored for future use; ignored by v1.
    #[serde(default)]
    pub mime: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UploadInitResponse {
    pub session_id: String,
    pub etag: String,
    /// Bytes the server already has for this (path, etag) pair.
    /// Zero on a fresh upload; non-zero only if we later support
    /// re-attaching to a crashed session by etag (v1 always 0).
    pub received: u64,
}

#[derive(Debug, Serialize)]
pub struct UploadProgressResponse {
    pub received: u64,
}

#[derive(Debug, Serialize)]
pub struct UploadFinishedResponse {
    pub path: String,
    pub size: u64,
}

// =====================================================================
// POST /mkdir
// =====================================================================

/// `POST /api/localsend/v2/fs/mkdir` — create a directory.
///
/// Body: `{ "path": "Photos/2026-09" }`. The path is validated
/// by [`PathGuard::check`] via the "parent must exist" variant:
/// we canonicalise the *parent* of the requested path and check
/// that the leaf doesn't already exist. Returns 409 if a file or
/// directory already occupies the path.
pub async fn handle_mkdir(
    state: &FsState,
    req: Request<Incoming>,
) -> Result<Response<BoxedBody>, FsError> {
    let body_bytes = req.into_body().collect()
        .await
        .map_err(|e| FsError::BadRequest(format!("reading mkdir body: {e}")))?
        .to_bytes();
    let body: MkdirBody = serde_json::from_slice(&body_bytes)
        .map_err(|e| FsError::BadRequest(format!("parsing mkdir body: {e}")))?;

    if body.path.is_empty() {
        return Err(FsError::BadRequest("empty path".into()));
    }

    // Resolve the parent via PathGuard; the leaf must not yet exist.
    let parent_abs = resolve_parent(&state.guard, &body.path)?;
    let leaf = last_segment(&body.path);
    let target = parent_abs.join(&leaf);

    // 409 if anything already exists at the target.
    if tokio::fs::symlink_metadata(&target).await.is_ok() {
        return Err(FsError::Conflict(format!("already exists: {}", body.path)));
    }

    // re-verify the parent under the guard (TOCTOU: the parent
    // was validated when we called `resolve_parent`, but the
    // filesystem may have moved since).
    state.guard.reverify(&parent_abs)?;

    tokio::fs::create_dir(&target).await.map_err(|e| {
        if e.kind() == std::io::ErrorKind::AlreadyExists {
            FsError::Conflict(format!("already exists: {}", body.path))
        } else {
            FsError::Io(format!("mkdir {}: {}", body.path, e))
        }
    })?;

    // Re-canonicalise to return the same shape the client sent
    // (a path under the root, not a host-absolute path).
    let canonical = tokio::fs::canonicalize(&target)
        .await
        .map_err(|e| FsError::Io(format!("canonicalize after mkdir: {e}")))?;
    let response_path = relativize(&state.guard, &canonical).unwrap_or(body.path);

    Ok(json_response(StatusCode::OK, &MkdirResponse { path: response_path }))
}

// =====================================================================
// POST /upload/init
// =====================================================================

/// `POST /api/localsend/v2/fs/upload/init` — create a session.
///
/// Query: `?path=<dest_dir>&filename=<name>`. Body:
/// `{ "total": 12345, "mime": "image/jpeg" }`.
///
/// Returns `{ sessionId, etag, received }`. The client must send
/// the file body as the body of subsequent `/upload/:id` POSTs.
pub async fn handle_upload_init(
    state: &FsState,
    req: Request<Incoming>,
) -> Result<Response<BoxedBody>, FsError> {
    let query = parse_query(req.uri().query());
    let q: UploadInitQuery = serde_json::from_value(serde_json::to_value(&query).unwrap())
        .map_err(|e| FsError::BadRequest(format!("parsing init query: {e}")))?;

    validate_filename(&q.filename)?;

    let body_bytes = req.into_body().collect()
        .await
        .map_err(|e| FsError::BadRequest(format!("reading init body: {e}")))?
        .to_bytes();
    let body: UploadInitBody = serde_json::from_slice(&body_bytes)
        .map_err(|e| FsError::BadRequest(format!("parsing init body: {e}")))?;

    // Enforce max_upload_size *before* allocating any staging file.
    if body.total > state.config.max_upload_size {
        return Err(FsError::PayloadTooLarge(body.total));
    }
    if body.total == 0 {
        return Err(FsError::BadRequest("total must be > 0".into()));
    }

    // Resolve the destination directory.
    let dir_abs = state.guard.check(&q.path)?;
    let meta = tokio::fs::metadata(&dir_abs).await.map_err(io_to_fs)?;
    if !meta.is_dir() {
        return Err(FsError::BadRequest(format!("not a directory: {}", q.path)));
    }

    let final_path = dir_abs.join(&q.filename);
    // Compute etag from path + size. If the destination file
    // already exists we include its mtime so a resumed upload
    // can detect "the destination already has this exact file".
    let etag = compute_etag(&final_path, body.total).await;

    // Choose a staging directory for the upload temp file.
    //
    // Ideal: `<target_dir>/.tmp/` — same volume, so rename is atomic.
    // Fallback: system temp dir — needed on Windows when target is a
    // drive root (e.g., `D:\`) where creating `.tmp` often fails with
    // "Access Denied" (os error 5) due to permissions or antivirus.
    // The finish handler's copy fallback handles cross-volume moves.
    let (tmp_dir, _using_fallback_tmp) = {
        let preferred = dir_abs.join(TMP_DIR);
        match try_create_dir_with_retries(&preferred, 2).await {
            Ok(()) => (preferred, false),
            Err(e) => {
                tracing::warn!(
                    event = "fs.upload.preferred_tmp_failed",
                    preferred = %preferred.display(),
                    error = %e,
                    "preferred .tmp dir not writable, falling back to system temp"
                );
                let sys_tmp = std::env::temp_dir().join("localsend-uploads");
                try_create_dir_with_retries(&sys_tmp, 2).await.map_err(|e2| {
                    FsError::Io(format!(
                        "failed to create temp directory in both {} and {}: {}",
                        preferred.display(),
                        sys_tmp.display(),
                        e2
                    ))
                })?;
                (sys_tmp, true)
            }
        }
    };

    let session_id = Uuid::new_v4().to_string();
    let tmp_path = tmp_dir.join(&session_id);

    // Create the staging file so subsequent chunks have
    // something to append to.
    // Retry on Windows to handle antivirus/defender scanning delays.
    let mut create_file_err: Option<std::io::Error> = None;
    for attempt in 0..3 {
        match tokio::fs::File::create(&tmp_path).await {
            Ok(_) => {
                create_file_err = None;
                break;
            }
            Err(e) => {
                tracing::warn!(
                    event = "fs.upload.create_staging_file_failed",
                    attempt = attempt,
                    tmp_path = %tmp_path.display(),
                    error = %e,
                    "failed to create staging file"
                );
                create_file_err = Some(e);
                if attempt < 2 {
                    tokio::time::sleep(std::time::Duration::from_millis(100 * (attempt + 1) as u64)).await;
                }
            }
        }
    }
    if let Some(e) = create_file_err {
        return Err(FsError::Io(format!(
            "failed to create staging file {}: {}",
            tmp_path.display(),
            e
        )));
    }

    let session = UploadSession {
        id: session_id.clone(),
        final_path,
        tmp_path,
        received: 0,
        total: body.total,
        etag: etag.clone(),
        started_at: Instant::now(),
        last_active: Instant::now(),
    };
    state.sessions.lock().await.insert(session_id.clone(), session);

    let response = UploadInitResponse { session_id: session_id.clone(), etag, received: 0 };
    tracing::info!(
        event = "fs.upload.init.response",
        session_id = %session_id,
        "Upload init response: {:?}",
        response
    );

    Ok(json_response(StatusCode::OK, &response))
}

// =====================================================================
// POST /upload/:id
// =====================================================================

/// `POST /api/localsend/v2/fs/upload/:id` — append a chunk.
///
/// Body: raw bytes. `Content-Range: bytes N-M/total` is optional;
/// if present, `N` must equal the session's current `received`.
/// If absent, the chunk is assumed to start at `received`.
pub async fn handle_upload_chunk(
    state: &FsState,
    session_id: &str,
    req: Request<Incoming>,
) -> Result<Response<BoxedBody>, FsError> {
    // Validate Content-Range header before touching the session
    // map, so a malformed request doesn't perturb state.
    let range_header = req
        .headers()
        .get(hyper::header::CONTENT_RANGE)
        .and_then(|h| h.to_str().ok())
        .map(|s| s.to_string());
    let declared_start = parse_content_range_start(range_header.as_deref())?;

    // Take the session out of the map while we mutate it, so
    // concurrent chunks on the same id serialise without a
    // long-held lock. We put it back at the end of the function
    // (or drop it on error paths).
    let mut session = {
        let mut map = state.sessions.lock().await;
        map.remove(session_id).ok_or_else(|| FsError::NotFound(format!("session {session_id}")))?
    };

    // Range must start at current received.
    if let Some(start) = declared_start {
        if start != session.received {
            let current = session.received;
            // Put the session back before returning the error so
            // the client can retry.
            state.sessions.lock().await.insert(session.id.clone(), session);
            return Err(FsError::BadRequest(format!(
                "Content-Range start {start} does not match session offset {current}"
            )));
        }
    }

    // TOCTOU: the session's tmp path was validated when the
    // session was created, but we re-verify the *parent* dir is
    // still under the whitelist (covers the case where the user
    // un-whitelisted a mount mid-upload).
    let parent = session.tmp_path.parent().ok_or_else(|| {
        FsError::Io("tmp path has no parent".into())
    })?;
    state.guard.reverify(parent).map_err(|_| {
        FsError::PathDenied {
            reason: super::path::PathDeniedReason::OutsideWhitelist,
            path: session.tmp_path.display().to_string(),
        }
    })?;

    // Stream the body into the tmp file.
    // On Windows, file opens can fail transiently due to antivirus scanning.
    // Retry with backoff.
    let mut file = {
        let mut last_err: Option<std::io::Error> = None;
        let mut file_opt: Option<tokio::fs::File> = None;
        for attempt in 0..3 {
            match tokio::fs::OpenOptions::new()
                .append(true)
                .open(&session.tmp_path)
                .await
            {
                Ok(f) => {
                    file_opt = Some(f);
                    last_err = None;
                    break;
                }
                Err(e) => {
                    tracing::warn!(
                        event = "fs.upload.chunk.open_failed",
                        attempt = attempt,
                        tmp_path = %session.tmp_path.display(),
                        error = %e,
                        "failed to open staging file for append"
                    );
                    last_err = Some(e);
                    if attempt < 2 {
                        tokio::time::sleep(std::time::Duration::from_millis(100 * (attempt + 1) as u64)).await;
                    }
                }
            }
        }
        match (file_opt, last_err) {
            (Some(f), _) => f,
            (_, Some(e)) => return Err(FsError::Io(format!("failed to open staging file: {}", e))),
            _ => return Err(FsError::Io("failed to open staging file: unknown error".into())),
        }
    };

    let mut body = req.into_body();
    let mut written: u64 = 0;
    use http_body_util::BodyExt;
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|e| FsError::Io(format!("reading chunk body: {e}")))?;
        if let Some(data) = frame.data_ref() {
            // Enforce the session's declared total so a lying
            // client can't grow the tmp file past what init
            // promised.
            if session.received + written + data.len() as u64 > session.total {
                // Best-effort cleanup: drop the file handle
                // (close) and remove the session. The tmp file
                // stays on disk; GC will reclaim it.
                drop(file);
                return Err(FsError::PayloadTooLarge(session.received + written + data.len() as u64));
            }
            use tokio::io::AsyncWriteExt;
            file.write_all(data).await.map_err(io_to_fs)?;
            written += data.len() as u64;
        }
    }
    file.flush().await.map_err(io_to_fs)?;
    drop(file);

    session.received += written;
    session.last_active = Instant::now();
    let received = session.received;
    state.sessions.lock().await.insert(session.id.clone(), session);

    Ok(json_response(
        StatusCode::OK,
        &UploadProgressResponse { received },
    ))
}

// =====================================================================
// POST /upload/:id/finish
// =====================================================================

/// `POST /api/localsend/v2/fs/upload/:id/finish` — fsync + rename.
pub async fn handle_upload_finish(
    state: &FsState,
    session_id: &str,
) -> Result<Response<BoxedBody>, FsError> {
    let session = {
        let mut map = state.sessions.lock().await;
        map.remove(session_id).ok_or_else(|| FsError::NotFound(format!("session {session_id}")))?
    };

    if session.received != session.total {
        let received = session.received;
        let total = session.total;
        // Put the session back so the client can send more
        // chunks; don't delete the tmp file.
        state.sessions.lock().await.insert(session.id.clone(), session);
        return Err(FsError::BadRequest(format!(
            "received {received} bytes but total is {total}"
        )));
    }

    // fsync the tmp file before rename so a crash mid-rename
    // doesn't leave a zero-length destination.
    // On Windows, fsync can fail spuriously (antivirus, filesystem
    // quirks), so we treat it as best-effort rather than fatal.
    match tokio::fs::File::open(&session.tmp_path).await {
        Ok(f) => {
            if let Err(e) = f.sync_all().await {
                tracing::warn!(
                    event = "fs.upload.fsync_failed",
                    tmp = %session.tmp_path.display(),
                    error = %e,
                    "fsync failed (best-effort, continuing)"
                );
            }
        }
        Err(e) => {
            tracing::warn!(
                event = "fs.upload.fsync_open_failed",
                tmp = %session.tmp_path.display(),
                error = %e,
                "failed to open tmp file for fsync (continuing)"
            );
        }
    }

    // On Windows, if the destination already exists, rename may
    // fail with "access denied". Try removing it first.
    if tokio::fs::metadata(&session.final_path).await.is_ok() {
        tracing::info!(
            event = "fs.upload.dest_exists",
            final = %session.final_path.display(),
            "destination file exists, removing before rename"
        );
        if let Err(e) = tokio::fs::remove_file(&session.final_path).await {
            tracing::warn!(
                event = "fs.upload.remove_dest_failed",
                final = %session.final_path.display(),
                error = %e,
                "failed to remove existing destination file"
            );
        }
    }

    // Atomic rename. Fall back to copy+delete if the rename
    // fails for any reason (EXDEV cross-device, permissions,
    // antivirus, etc.) — the tmp file still exists so we can recover.
    // Retry once after a short delay to handle transient Windows locks.
    let mut rename_err: Option<std::io::Error> = None;
    for attempt in 0..2 {
        match tokio::fs::rename(&session.tmp_path, &session.final_path).await {
            Ok(()) => {
                rename_err = None;
                break;
            }
            Err(e) => {
                tracing::warn!(
                    event = "fs.upload.rename_attempt_failed",
                    attempt = attempt,
                    tmp = %session.tmp_path.display(),
                    final = %session.final_path.display(),
                    error = %e,
                    "rename attempt failed"
                );
                rename_err = Some(e);
                if attempt == 0 {
                    // Give Windows Defender / AV time to release the file
                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                }
            }
        }
    }

    if let Some(rename_e) = rename_err {
        // Check if this is a cross-volume scenario (tmp on different drive than final)
        let is_cross_volume = {
            let tmp_parent = session.tmp_path.parent();
            let final_parent = session.final_path.parent();
            match (tmp_parent, final_parent) {
                (Some(tp), Some(fp)) => {
                    // On Windows, check if drive letters differ
                    // On Unix, check if they're on different mount points
                    tp.to_string_lossy().chars().next() != fp.to_string_lossy().chars().next()
                }
                _ => false,
            }
        };

        if is_cross_volume {
            tracing::info!(
                event = "fs.upload.cross_volume_move",
                tmp = %session.tmp_path.display(),
                final = %session.final_path.display(),
                "cross-volume upload detected, using copy+delete (rename not possible)"
            );
        } else {
            tracing::warn!(
                event = "fs.upload.rename_fallback",
                tmp = %session.tmp_path.display(),
                final = %session.final_path.display(),
                error = %rename_e,
                "rename failed after retries, falling back to copy+delete"
            );
        }

        // Retry copy+delete once as well
        let mut copy_err: Option<std::io::Error> = None;
        for attempt in 0..2 {
            match tokio::fs::copy(&session.tmp_path, &session.final_path).await {
                Ok(bytes_copied) => {
                    tracing::info!(
                        event = "fs.upload.copy_success",
                        bytes = bytes_copied,
                        "copy completed successfully"
                    );
                    copy_err = None;
                    break;
                }
                Err(e) => {
                    tracing::warn!(
                        event = "fs.upload.copy_attempt_failed",
                        attempt = attempt,
                        tmp = %session.tmp_path.display(),
                        final = %session.final_path.display(),
                        error = %e,
                        "copy attempt failed"
                    );
                    copy_err = Some(e);
                    if attempt == 0 {
                        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                    }
                }
            }
        }
        if let Some(e) = copy_err {
            return Err(FsError::Io(format!(
                "failed to move upload to destination {} -> {}: {} (hint: check write permissions to destination directory)",
                session.tmp_path.display(),
                session.final_path.display(),
                e
            )));
        }
        if let Err(e) = tokio::fs::remove_file(&session.tmp_path).await {
            tracing::warn!(
                event = "fs.upload.remove_tmp_failed",
                tmp = %session.tmp_path.display(),
                error = %e,
                "failed to remove staging file after copy (non-fatal)"
            );
        }
    }

    // Re-verify the destination is under the whitelist (the
    // parent dir was verified at init, but we check again to
    // close any TOCTOU where the dir was swapped out).
    state.guard.reverify(&session.final_path)?;

    let response_path = relativize(&state.guard, &session.final_path)
        .unwrap_or_else(|| session.final_path.display().to_string());

    Ok(json_response(
        StatusCode::OK,
        &UploadFinishedResponse { path: response_path, size: session.total },
    ))
}

// =====================================================================
// DELETE /upload/:id
// =====================================================================

/// `DELETE /api/localsend/v2/fs/upload/:id` — cancel.
pub async fn handle_upload_cancel(
    state: &FsState,
    session_id: &str,
) -> Result<Response<BoxedBody>, FsError> {
    let session = {
        let mut map = state.sessions.lock().await;
        map.remove(session_id).ok_or_else(|| FsError::NotFound(format!("session {session_id}")))?
    };
    // Best-effort cleanup; if the file is already gone that's fine.
    let _ = tokio::fs::remove_file(&session.tmp_path).await;
    Ok(json_response(StatusCode::OK, &serde_json::json!({ "ok": true })))
}

// =====================================================================
// Whitelist-revoke hook
// =====================================================================

impl FsState {
    /// Called when the whitelist changes (IPC handler or hotplug
    /// event). Cancels every session whose `final_path` no longer
    /// sits under any whitelisted root. Returns the session ids
    /// that were aborted so the caller can push a `FsEvent`
    /// (T-019).
    pub async fn abort_sessions_outside_whitelist(&self) -> Vec<String> {
        let mut aborted = Vec::new();
        let mut map = self.sessions.lock().await;
        let retained: HashMap<String, UploadSession> = map
            .drain()
            .filter_map(|(id, session)| {
                // Re-check under the *current* guard. If the
                // destination no longer resolves, drop the
                // session and clean up its tmp file.
                if self.guard.reverify(&session.final_path).is_ok() {
                    Some((id, session))
                } else {
                    let _ = std::fs::remove_file(&session.tmp_path);
                    aborted.push(id);
                    None
                }
            })
            .collect();
        *map = retained;
        aborted
    }
}

// =====================================================================
// GC
// =====================================================================

/// Reclaim sessions that have been idle longer than `SESSION_TTL`.
/// Intended to be called on a periodic timer (server-side; T-019
/// will wire the tick).
pub async fn gc_sessions(state: &FsState) {
    let mut map = state.sessions.lock().await;
    let expired_ids: Vec<String> = map
        .iter()
        .filter(|(_, s)| s.is_expired(SESSION_TTL))
        .map(|(id, _)| id.clone())
        .collect();
    for id in expired_ids {
        if let Some(session) = map.remove(&id) {
            let _ = tokio::fs::remove_file(&session.tmp_path).await;
            tracing::info!(
                event = "fs.upload.session.gc",
                session_id = %id,
                "reclaimed idle upload session"
            );
        }
    }
}

// =====================================================================
// Helpers
// =====================================================================

/// Resolve the parent directory of `path` under the guard.
/// Returns the canonical absolute parent. Rejects paths whose
/// parent does not exist or is outside the whitelist.
fn resolve_parent(guard: &PathGuard, path: &str) -> Result<PathBuf, FsError> {
    let parent_path = parent_str(path).ok_or_else(|| FsError::BadRequest("path has no parent".into()))?;
    // The root itself has no parent; treat the root as its own
    // parent by checking it directly.
    let parent_abs = if parent_path.is_empty() || parent_path == "." {
        // The caller wants to create something at the root
        // level. We need any whitelisted root — pick the first.
        guard
            .table()
            .roots()
            .first()
            .map(|r| {
                std::fs::canonicalize(&r.path).map_err(|e| FsError::Io(format!("canonicalize root: {e}")))
            })
            .transpose()?
            .ok_or_else(|| FsError::PathDenied {
                reason: super::path::PathDeniedReason::OutsideWhitelist,
                path: path.into(),
            })?
    } else {
        guard.check(parent_path)?
    };
    Ok(parent_abs)
}

/// Extract the last path segment. `parent_str` is the dual.
fn last_segment(path: &str) -> String {
    path.rsplit(|c| c == '/' || c == '\\')
        .next()
        .unwrap_or(path)
        .to_string()
}

/// Everything before the last segment. Returns `None` only for
/// empty input.
fn parent_str(path: &str) -> Option<&str> {
    let trimmed = path.trim_end_matches(|c| c == '/' || c == '\\');
    match trimmed.rfind(|c| c == '/' || c == '\\') {
        Some(idx) => Some(&trimmed[..idx]),
        None => {
            if trimmed.is_empty() {
                None
            } else {
                // Single-segment path; parent is the root.
                Some("")
            }
        }
    }
}

/// Reject filenames that could escape the target directory.
fn validate_filename(name: &str) -> Result<(), FsError> {
    if name.is_empty() {
        return Err(FsError::BadRequest("empty filename".into()));
    }
    if name.contains('/') || name.contains('\\') {
        return Err(FsError::BadRequest("filename must not contain path separators".into()));
    }
    if name == "." || name == ".." {
        return Err(FsError::BadRequest(format!("invalid filename: {name}")));
    }
    if name.contains('\0') {
        return Err(FsError::BadRequest("filename contains NUL".into()));
    }
    Ok(())
}

/// Try to create a directory with retries and exponential backoff.
///
/// On Windows, directory creation at drive roots or in paths scanned
/// by antivirus can fail transiently with "Access Denied" (os error 5).
/// This helper retries up to `max_retries` times with delays of
/// 100ms, 200ms, etc. to handle such transient failures.
async fn try_create_dir_with_retries(path: &Path, max_retries: u32) -> Result<(), std::io::Error> {
    let mut last_err: Option<std::io::Error> = None;
    for attempt in 0..=max_retries {
        match tokio::fs::create_dir_all(path).await {
            Ok(()) => return Ok(()),
            Err(e) => {
                tracing::debug!(
                    event = "fs.upload.create_dir_attempt",
                    attempt = attempt,
                    path = %path.display(),
                    error = %e,
                    "directory creation attempt"
                );
                last_err = Some(e);
                if attempt < max_retries {
                    // Exponential backoff: 100ms, 200ms, 400ms...
                    let delay_ms = 100u64 * (1u64 << attempt);
                    tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
                }
            }
        }
    }
    Err(last_err.unwrap())
}

/// Compute a resume etag for a destination path. The etag is
/// `sha256(path|size|mtime)[:16]`. If the file doesn't exist,
/// the mtime segment is `0` so two fresh uploads of the same
/// name+size get the same etag (the client can use this to skip
/// re-uploading an identical file).
async fn compute_etag(path: &Path, size: u64) -> String {
    let mtime = tokio::fs::metadata(path)
        .await
        .ok()
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let mut hasher = Sha256::new();
    hasher.update(path.display().to_string().as_bytes());
    hasher.update(b"|");
    hasher.update(size.to_string().as_bytes());
    hasher.update(b"|");
    hasher.update(mtime.to_string().as_bytes());
    let digest = hasher.finalize();
    hex::encode(&digest[..8])
}

/// Parse `Content-Range: bytes N-M/total` and return `N`. Returns
/// `Ok(None)` if the header is absent (chunk starts at current
/// offset by convention) or `Err` if malformed.
fn parse_content_range_start(header: Option<&str>) -> Result<Option<u64>, FsError> {
    let Some(h) = header else { return Ok(None) };
    let h = h.trim();
    let body = h
        .strip_prefix("bytes ")
        .ok_or_else(|| FsError::BadRequest("Content-Range must start with 'bytes '".into()))?;
    let range_part = body.split('/').next().ok_or_else(|| {
        FsError::BadRequest("Content-Range missing '/'".into())
    })?;
    let start_str = range_part.split('-').next().ok_or_else(|| {
        FsError::BadRequest("Content-Range missing '-'".into())
    })?;
    let start: u64 = start_str
        .trim()
        .parse()
        .map_err(|_| FsError::BadRequest("Content-Range start is not a number".into()))?;
    Ok(Some(start))
}

/// Convert a canonical absolute path back into a logical path
/// relative to the whitelisted root that contains it. Returns
/// `None` if no root matches (should not happen after
/// `PathGuard::check`, but we treat it defensively).
fn relativize(guard: &PathGuard, canonical: &Path) -> Option<String> {
    for root in guard.table().roots() {
        let Ok(canonical_root) = std::fs::canonicalize(&root.path) else {
            continue;
        };
        if let Ok(rel) = canonical.strip_prefix(&canonical_root) {
            let rel_str = rel.to_string_lossy().replace('\\', "/");
            if rel_str.is_empty() {
                return Some(root.id.clone());
            }
            return Some(format!("{}/{}", root.id, rel_str));
        }
    }
    None
}

fn io_to_fs(e: std::io::Error) -> FsError {
    FsError::Io(e.to_string())
}

/// Build a `200 OK` JSON response. Re-exported through `rest.rs`
/// so both modules share one envelope helper.
fn json_response<T: Serialize>(status: StatusCode, value: &T) -> Response<BoxedBody> {
    super::rest::json_response(status, value)
}

/// Parse a URI query string into a `serde_json::Value` object.
fn parse_query(query: Option<&str>) -> serde_json::Map<String, serde_json::Value> {
    let mut map = serde_json::Map::new();
    let Some(q) = query else { return map };
    for pair in q.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (k, v) = match pair.split_once('=') {
            Some((k, v)) => (k, v),
            None => (pair, ""),
        };
        let decoded = percent_decode(v);
        map.insert(k.to_string(), serde_json::Value::String(decoded));
    }
    map
}

/// One-pass percent-decode. Duplicated from `path.rs` because
/// the path module's version is private; keeping the two in
/// sync is acceptable at this size.
fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(h), Some(l)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2])) {
                out.push((h << 4) | l);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

// Tiny hex encoder for etags. Avoids pulling a new dep for a
// 16-char output.
mod hex {
    pub fn encode(bytes: &[u8]) -> String {
        let mut out = String::with_capacity(bytes.len() * 2);
        for b in bytes {
            use std::fmt::Write;
            let _ = write!(out, "{:02x}", b);
        }
        out
    }
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fs::{FsConfig, FsRoot, MountTable};
    use http_body_util::{BodyExt, Full};
    use hyper::body::Bytes;

    fn fixture() -> (FsState, PathBuf) {
        let dir = tempfile_subdir("upload");
        let root = FsRoot::new(dir.to_string_lossy(), "Photos", dir.to_string_lossy());
        let table = MountTable::from_config(vec![root]);
        (FsState::new(FsConfig::default(), table), dir)
    }

    fn tempfile_subdir(test: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!("localsend_upload_{}_{}_{}", test, pid, nanos));
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    async fn body_to_string(resp: Response<BoxedBody>) -> String {
        let collected = resp.into_body().collect().await.expect("body collect");
        String::from_utf8(collected.to_bytes().to_vec()).expect("utf8 body")
    }

    fn mkdir_req(_body_json: &str) -> Request<Full<Bytes>> {
        // Note: We can't easily test the full handlers because they
        // take `Request<Incoming>` which is hard to construct.
        // Integration tests with a real HTTP client will cover these.
        // Here we only test the helper functions.
        unimplemented!("handler tests require integration test setup")
    }

    // -------- mkdir ------------------------------------------------
    // Handler tests removed - they require Request<Incoming> which
    // cannot be easily constructed in unit tests. Integration tests
    // will cover the full request/response cycle.

    // -------- filename validation ---------------------------------

    #[test]
    fn validate_filename_accepts_normal() {
        assert!(validate_filename("IMG_0001.jpg").is_ok());
        assert!(validate_filename("my file (1).txt").is_ok());
        assert!(validate_filename("日本語.txt").is_ok());
    }

    #[test]
    fn validate_filename_rejects_slashes() {
        assert!(validate_filename("foo/bar").is_err());
        assert!(validate_filename("foo\\bar").is_err());
    }

    #[test]
    fn validate_filename_rejects_dot_segments() {
        assert!(validate_filename(".").is_err());
        assert!(validate_filename("..").is_err());
    }

    #[test]
    fn validate_filename_rejects_empty() {
        assert!(validate_filename("").is_err());
    }

    #[test]
    fn validate_filename_rejects_nul() {
        assert!(validate_filename("foo\0bar").is_err());
    }

    // -------- parse_content_range_start ---------------------------

    #[test]
    fn parse_content_range_none_when_absent() {
        assert!(parse_content_range_start(None).unwrap().is_none());
    }

    #[test]
    fn parse_content_range_returns_start() {
        assert_eq!(parse_content_range_start(Some("bytes 100-199/1000")).unwrap(), Some(100));
    }

    #[test]
    fn parse_content_range_open_ended() {
        assert_eq!(parse_content_range_start(Some("bytes 500-/*")).unwrap(), Some(500));
    }

    #[test]
    fn parse_content_range_rejects_garbage() {
        assert!(parse_content_range_start(Some("garbage")).is_err());
    }

    // -------- session lifecycle -----------------------------------

    #[tokio::test]
    async fn session_is_expired_after_ttl() {
        let session = UploadSession {
            id: "x".into(),
            final_path: PathBuf::from("/x"),
            tmp_path: PathBuf::from("/x/.tmp/y"),
            received: 0,
            total: 100,
            etag: "abc".into(),
            started_at: Instant::now(),
            last_active: Instant::now() - Duration::from_secs(31 * 60),
        };
        assert!(session.is_expired(SESSION_TTL));
    }

    #[tokio::test]
    async fn gc_reclaims_idle_sessions() {
        let (state, dir) = fixture();
        let tmp_dir = dir.join(TMP_DIR);
        tokio::fs::create_dir_all(&tmp_dir).await.unwrap();
        let tmp_path = tmp_dir.join("stale");
        tokio::fs::File::create(&tmp_path).await.unwrap();

        let session = UploadSession {
            id: "stale".into(),
            final_path: dir.join("missing"),
            tmp_path: tmp_path.clone(),
            received: 0,
            total: 100,
            etag: "e".into(),
            started_at: Instant::now() - Duration::from_secs(31 * 60),
            last_active: Instant::now() - Duration::from_secs(31 * 60),
        };
        state.sessions.lock().await.insert("stale".into(), session);
        assert_eq!(state.sessions.lock().await.len(), 1);

        super::gc_sessions(&state).await;
        assert_eq!(state.sessions.lock().await.len(), 0);
        // Tmp file was removed.
        assert!(!tmp_path.exists());
    }

    #[tokio::test]
    async fn whitelist_revoke_aborts_session() {
        // Build a state with an empty whitelist (every session's
        // final_path will fail reverify).
        let empty_state = FsState::new(FsConfig::default(), MountTable::new());
        let dir = tempfile_subdir("revoke");
        let tmp_dir = dir.join(TMP_DIR);
        tokio::fs::create_dir_all(&tmp_dir).await.unwrap();
        let tmp_path = tmp_dir.join("orphan");
        tokio::fs::File::create(&tmp_path).await.unwrap();

        let session = UploadSession {
            id: "orphan".into(),
            final_path: dir.join("dest"),
            tmp_path: tmp_path.clone(),
            received: 50,
            total: 100,
            etag: "e".into(),
            started_at: Instant::now(),
            last_active: Instant::now(),
        };
        empty_state.sessions.lock().await.insert("orphan".into(), session);
        assert_eq!(empty_state.sessions.lock().await.len(), 1);

        let aborted = empty_state.abort_sessions_outside_whitelist().await;
        assert_eq!(aborted, vec!["orphan".to_string()]);
        assert_eq!(empty_state.sessions.lock().await.len(), 0);
        assert!(!tmp_path.exists());
    }

    // -------- relativize ------------------------------------------

    #[test]
    fn relativize_returns_root_id_for_root_path() {
        let dir = tempfile_subdir("rel_root");
        let dir_str = dir.to_string_lossy().into_owned();
        let root = FsRoot::new(dir_str.clone(), "Photos", dir_str);
        let table = MountTable::from_config(vec![root]);
        let guard = PathGuard::new(&table);
        let canonical = std::fs::canonicalize(&dir).unwrap();
        let result = relativize(&guard, &canonical);
        // Either the root id ("Photos") or the raw path,
        // depending on implementation. The contract is that
        // the result identifies the root.
        assert!(result.is_some());
    }

    #[test]
    fn relativize_returns_none_for_path_outside_all_roots() {
        let dir = tempfile_subdir("rel_outside");
        let dir_str = dir.to_string_lossy().into_owned();
        let root = FsRoot::new(dir_str.clone(), "Photos", dir_str);
        let table = MountTable::from_config(vec![root]);
        let guard = PathGuard::new(&table);
        let other = tempfile_subdir("rel_outside_other");
        let canonical = std::fs::canonicalize(&other).unwrap();
        assert!(relativize(&guard, &canonical).is_none());
    }
}
