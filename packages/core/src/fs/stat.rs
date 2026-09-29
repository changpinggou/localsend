//! Stat endpoint for the `fs` module (T-014).
//!
//! `GET /api/localsend/v2/fs/stat` — fetch metadata for a single file.
//! Used by clients for:
//! - Resume validation (etag matches upload session)
//! - Media player pre-probe (size, mime, range support)
//! - File properties display

use std::time::SystemTime;

use hyper::{Request, Response, StatusCode};
use serde::{Deserialize, Serialize};

use super::path::FsError;
use super::rest::{guess_mime, json_response, FsState};
use crate::http::server::common::query::parse_query;
use crate::http::server::common::response::BoxedBody;

/// Query parameters for `GET /fs/stat`.
#[derive(Debug, Deserialize)]
pub struct StatParams {
    /// Path relative to whitelist root.
    pub path: String,
}

/// Response body for `GET /fs/stat`.
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StatResponse {
    /// Filename (basename, not full path).
    pub name: String,
    /// `true` if directory, `false` if file.
    pub is_dir: bool,
    /// File size in bytes. `0` for directories.
    pub size: u64,
    /// Modification time as Unix epoch seconds.
    pub mtime: i64,
    /// MIME type guess based on extension. `None` for directories.
    pub mime: Option<String>,
    /// Whether the file supports HTTP Range requests. Always `true` for files.
    pub supports_range: bool,
    /// ETag for resume validation. Hash of mtime + size.
    pub etag: String,
}

impl StatResponse {
    /// Deserialize from a JSON value.
    pub fn from_json(json: serde_json::Value) -> Self {
        serde_json::from_value(json).unwrap_or(StatResponse {
            name: String::new(),
            is_dir: false,
            size: 0,
            mtime: 0,
            mime: None,
            supports_range: false,
            etag: String::new(),
        })
    }
}

/// `GET /api/localsend/v2/fs/stat` — fetch metadata for a single file/directory.
///
/// ## Algorithm
///
/// 1. Parse `path` query parameter.
/// 2. Validate through `PathGuard`.
/// 3. Fetch metadata via `tokio::fs::metadata`.
/// 4. Compute etag from mtime + size.
/// 5. Return JSON response.
///
/// ## Errors
///
/// - `400 BadRequest` — missing `path` parameter.
/// - `403 PathDenied` — path outside whitelist.
/// - `404 NotFound` — path doesn't exist.
pub async fn handle_stat(
    state: &FsState,
    req: &Request<impl hyper::body::Body>,
) -> Result<Response<BoxedBody>, FsError> {
    let query = parse_query(req.uri().query());
    let path = query
        .get("path")
        .cloned()
        .ok_or_else(|| FsError::BadRequest("missing 'path'".into()))?;

    let abs = state.guard.check(&path)?;
    let meta = tokio::fs::metadata(&abs).await.map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            FsError::NotFound(format!("path not found: {}", path))
        } else {
            FsError::Io(e.to_string())
        }
    })?;

    let name = abs
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();

    let is_dir = meta.is_dir();
    let size = if is_dir { 0 } else { meta.len() };

    let mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let mime = if is_dir {
        None
    } else {
        Some(guess_mime(&name).to_string())
    };

    let supports_range = !is_dir;

    // ETag: hash of mtime + size for resume validation
    let etag = compute_etag(mtime, size);

    Ok(json_response(
        StatusCode::OK,
        &StatResponse {
            name,
            is_dir,
            size,
            mtime,
            mime,
            supports_range,
            etag,
        },
    ))
}

/// Compute an ETag from mtime and size.
///
/// Format: `"<mtime>-<size>"` (quoted, as per HTTP spec).
/// Used for resume validation: if the file changes, the etag changes,
/// and the client knows to restart the upload/download.
fn compute_etag(mtime: i64, size: u64) -> String {
    format!("\"{}-{}\"", mtime, size)
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fs::{FsConfig, FsRoot, MountTable};
    use std::path::PathBuf;

    fn fixture() -> (FsState, PathBuf) {
        let dir = tempfile_subdir("stat");
        let dir_str = dir.to_string_lossy().into_owned();
        let root = FsRoot::new(dir_str.clone(), "TestRoot", dir_str);
        let table = MountTable::from_config(vec![root]);
        let config = FsConfig::default();
        (FsState::new(config, table), dir)
    }

    fn tempfile_subdir(test: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!("localsend_stat_{}_{}_{}", test, pid, nanos));
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    #[tokio::test]
    async fn stat_returns_etag_consistent() {
        let (state, dir) = fixture();
        let file = dir.join("test.txt");
        std::fs::write(&file, "hello world").unwrap();

        let path = "test.txt".to_string();
        let abs = state.guard.check(&path).unwrap();
        let meta = tokio::fs::metadata(&abs).await.unwrap();

        let mtime = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let size = meta.len();
        let etag = compute_etag(mtime, size);

        // ETag should be quoted
        assert!(etag.starts_with('"'));
        assert!(etag.ends_with('"'));

        // ETag should contain mtime and size
        assert!(etag.contains(&mtime.to_string()));
        assert!(etag.contains(&size.to_string()));

        // Same file should produce same etag
        let etag2 = compute_etag(mtime, size);
        assert_eq!(etag, etag2);
    }

    #[tokio::test]
    async fn stat_rejects_path_outside_whitelist() {
        let (state, _) = fixture();
        let path = "../etc/passwd".to_string();
        let result = state.guard.check(&path);
        assert!(result.is_err());
    }
}
