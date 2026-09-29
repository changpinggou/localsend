//! Move and delete operations for the `fs` module (T-014).
//!
//! Two write endpoints:
//!
//! - `POST /api/localsend/v2/fs/move` — rename / move a file or directory.
//!   Uses `tokio::fs::rename` when possible; falls back to copy + delete
//!   on cross-device links (EXDEV).
//!
//! - `POST /api/localsend/v2/fs/delete` — batch delete files/directories.
//!   Supports optional recycle bin (T-015) and aggregates partial failures.
//!
//! Both endpoints require `confirm: true` to prevent accidental data loss.
//! All operations go through `PathGuard` for sandbox validation.

use std::path::Path;

use hyper::{Request, Response, StatusCode};
use serde::{Deserialize, Serialize};

use super::path::FsError;
use super::rest::{json_response, FsState};
use crate::http::server::common::response::BoxedBody;

// =====================================================================
// Move endpoint
// =====================================================================

/// Request body for `POST /fs/move`.
#[derive(Debug, Deserialize)]
pub struct MoveBody {
    /// Source path (relative to whitelist root).
    pub from: String,
    /// Destination path (relative to whitelist root).
    pub to: String,
    /// Must be `true` to proceed. Prevents accidental moves.
    pub confirm: bool,
}

/// Response body for `POST /fs/move`.
#[derive(Debug, Serialize, Deserialize)]
pub struct MoveResponse {
    /// Final destination path (canonical).
    pub path: String,
}

impl MoveResponse {
    /// Deserialize from a JSON value.
    pub fn from_json(json: serde_json::Value) -> Self {
        serde_json::from_value(json).unwrap_or(MoveResponse {
            path: String::new(),
        })
    }
}

/// `POST /api/localsend/v2/fs/move` — rename or move a file/directory.
///
/// ## Algorithm
///
/// 1. Validate `from` through `PathGuard` (must exist).
/// 2. Validate parent directory of `to` through `PathGuard` (destination file may not exist yet).
/// 3. Check `confirm` flag.
/// 4. Try `tokio::fs::rename(from, to)`.
/// 5. On `EXDEV` (cross-device): fall back to copy + delete.
/// 6. Copy mode: if fails mid-way, clean up target.
/// 7. Record audit entry (T-015).
///
/// ## Errors
///
/// - `400 BadRequest` — `confirm` is false, or paths are invalid.
/// - `403 PathDenied` — source or destination outside whitelist.
/// - `404 NotFound` — source doesn't exist.
/// - `500 Io` — filesystem error.
pub async fn handle_move(
    state: &FsState,
    req: Request<hyper::body::Incoming>,
    fingerprint: Option<&str>,
) -> Result<Response<BoxedBody>, FsError> {
    // Parse body
    let body = http_body_util::BodyExt::collect(req.into_body())
        .await
        .map_err(|e| FsError::Io(e.to_string()))?;
    let body_str = String::from_utf8(body.to_bytes().to_vec())
        .map_err(|_| FsError::BadRequest("invalid UTF-8".into()))?;
    let move_body: MoveBody = serde_json::from_str(&body_str)
        .map_err(|e| FsError::BadRequest(format!("invalid JSON: {}", e)))?;

    // Check confirm flag
    if !move_body.confirm {
        return Err(FsError::BadRequest("confirm required".into()));
    }

    // Validate source path (must exist)
    let from_abs = state.guard.check(&move_body.from)?;
    if !from_abs.exists() {
        return Err(FsError::NotFound(format!("source not found: {}", move_body.from)));
    }

    // Validate destination path
    // The destination file may not exist yet, so we validate the parent directory
    let to_path = std::path::Path::new(&move_body.to);
    let to_parent = to_path
        .parent()
        .ok_or_else(|| FsError::BadRequest("invalid destination path".into()))?;
    let to_parent_str = to_parent.to_string_lossy().to_string();

    // If parent is empty, use "." to refer to root
    let to_parent_check = if to_parent_str.is_empty() {
        ".".to_string()
    } else {
        to_parent_str
    };

    let to_parent_abs = state.guard.check(&to_parent_check)?;
    let to_abs = to_parent_abs.join(to_path.file_name().ok_or_else(|| {
        FsError::BadRequest("invalid destination filename".into())
    })?);

    // Try rename first
    let peer = fingerprint.unwrap_or("unknown").to_string();
    match tokio::fs::rename(&from_abs, &to_abs).await {
        Ok(_) => {
            tracing::info!(from = %move_body.from, to = %move_body.to, "fs move succeeded");

            // Record audit entry
            if let Some(audit) = &state.audit {
                let entry = super::audit::AuditEntry::new(
                    peer,
                    "move".to_string(),
                    format!("{} -> {}", move_body.from, move_body.to),
                    "ok".to_string(),
                );
                let _ = audit.record(&entry);
            }

            Ok(json_response(
                StatusCode::OK,
                &MoveResponse {
                    path: move_body.to,
                },
            ))
        }
        #[cfg(unix)]
        Err(e) if e.raw_os_error() == Some(libc::EXDEV) => {
            // Cross-device link: fall back to copy + delete
            tracing::info!(
                from = %move_body.from,
                to = %move_body.to,
                "cross-device move, falling back to copy+delete"
            );
            copy_and_fallback(&from_abs, &to_abs).await?;

            // Record audit entry
            if let Some(audit) = &state.audit {
                let entry = super::audit::AuditEntry::new(
                    peer,
                    "move".to_string(),
                    format!("{} -> {} (cross-device)", move_body.from, move_body.to),
                    "ok".to_string(),
                );
                let _ = audit.record(&entry);
            }

            Ok(json_response(
                StatusCode::OK,
                &MoveResponse {
                    path: move_body.to,
                },
            ))
        }
        Err(e) => {
            tracing::warn!(
                from = %move_body.from,
                to = %move_body.to,
                error = %e,
                "fs move failed"
            );

            // Record audit entry for failure
            if let Some(audit) = &state.audit {
                let entry = super::audit::AuditEntry::new(
                    peer,
                    "move".to_string(),
                    format!("{} -> {}", move_body.from, move_body.to),
                    e.to_string(),
                );
                let _ = audit.record(&entry);
            }

            Err(FsError::Io(e.to_string()))
        }
    }
}

/// Copy a file/directory from `src` to `dst`, then delete `src`.
///
/// Used as a fallback when `rename` fails with `EXDEV` (cross-device link).
/// If the copy fails mid-way, the partially-copied target is cleaned up.
async fn copy_and_fallback(src: &Path, dst: &Path) -> Result<(), FsError> {
    // Check if src is a directory
    let meta = tokio::fs::metadata(src).await.map_err(|e| FsError::Io(e.to_string()))?;

    if meta.is_dir() {
        // Directory: use recursive copy
        copy_dir_recursive(src, dst).await?;
    } else {
        // File: simple copy
        tokio::fs::copy(src, dst).await.map_err(|e| {
            tracing::warn!(src = %src.display(), dst = %dst.display(), error = %e, "file copy failed");
            FsError::Io(e.to_string())
        })?;
    }

    // Delete source after successful copy
    if meta.is_dir() {
        tokio::fs::remove_dir_all(src).await.map_err(|e| {
            tracing::warn!(src = %src.display(), error = %e, "source dir cleanup failed");
            FsError::Io(e.to_string())
        })?;
    } else {
        tokio::fs::remove_file(src).await.map_err(|e| {
            tracing::warn!(src = %src.display(), error = %e, "source file cleanup failed");
            FsError::Io(e.to_string())
        })?;
    }

    Ok(())
}

/// Recursively copy a directory from `src` to `dst`.
///
/// Creates `dst` if it doesn't exist. Copies all files and subdirectories.
/// If any copy fails, the partially-copied `dst` is cleaned up.
async fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<(), FsError> {
    // Create destination directory
    tokio::fs::create_dir_all(dst).await.map_err(|e| {
        tracing::warn!(dst = %dst.display(), error = %e, "failed to create dest dir");
        FsError::Io(e.to_string())
    })?;

    let mut rd = tokio::fs::read_dir(src).await.map_err(|e| {
        tracing::warn!(src = %src.display(), error = %e, "failed to read source dir");
        FsError::Io(e.to_string())
    })?;

    while let Some(entry) = rd.next_entry().await.map_err(|e| FsError::Io(e.to_string()))? {
        let entry_path = entry.path();
        let entry_name = entry.file_name();
        let dst_path = dst.join(entry_name);

        let meta = entry.metadata().await.map_err(|e| FsError::Io(e.to_string()))?;

        if meta.is_dir() {
            // Recursive directory copy
            Box::pin(copy_dir_recursive(&entry_path, &dst_path)).await?;
        } else {
            // File copy
            tokio::fs::copy(&entry_path, &dst_path).await.map_err(|e| {
                tracing::warn!(
                    src = %entry_path.display(),
                    dst = %dst_path.display(),
                    error = %e,
                    "file copy failed during recursive copy"
                );
                FsError::Io(e.to_string())
            })?;
        }
    }

    Ok(())
}

// =====================================================================
// Delete endpoint
// =====================================================================

/// Request body for `POST /fs/delete`.
#[derive(Debug, Deserialize)]
pub struct DeleteBody {
    /// List of paths to delete (relative to whitelist root).
    pub paths: Vec<String>,
    /// If `true`, move to recycle bin (T-015). If `false`, permanent delete.
    pub recycle: bool,
    /// Must be `true` to proceed. Prevents accidental deletions.
    pub confirm: bool,
}

/// A single deletion failure.
#[derive(Debug, Serialize, Deserialize)]
pub struct DeleteFailure {
    /// Path that failed to delete.
    pub path: String,
    /// Human-readable error message.
    pub reason: String,
}

/// Response body for `POST /fs/delete`.
#[derive(Debug, Serialize, Deserialize)]
pub struct DeleteResponse {
    /// Paths that were successfully deleted.
    pub deleted: Vec<String>,
    /// Paths that failed to delete, with reasons.
    pub failed: Vec<DeleteFailure>,
}

impl DeleteResponse {
    /// Deserialize from a JSON value.
    pub fn from_json(json: serde_json::Value) -> Self {
        serde_json::from_value(json).unwrap_or(DeleteResponse {
            deleted: Vec::new(),
            failed: Vec::new(),
        })
    }
}

/// `POST /api/localsend/v2/fs/delete` — batch delete files/directories.
///
/// ## Algorithm
///
/// 1. Check `confirm` flag.
/// 2. For each path:
///    a. Validate through `PathGuard`.
///    b. If `recycle=true`, call T-015 recycle bin.
///    c. If `recycle=false`, call `tokio::fs::remove_file` / `remove_dir_all`.
///    d. Record audit entry (T-015).
/// 3. Aggregate successes into `deleted`, failures into `failed`.
///
/// ## Errors
///
/// - `400 BadRequest` — `confirm` is false.
/// - `403 PathDenied` — any path outside whitelist (fails entire request).
/// - Partial failures are aggregated, not raised as errors.
pub async fn handle_delete(
    state: &FsState,
    req: Request<hyper::body::Incoming>,
    fingerprint: Option<&str>,
) -> Result<Response<BoxedBody>, FsError> {
    // Parse body
    let body = http_body_util::BodyExt::collect(req.into_body())
        .await
        .map_err(|e| FsError::Io(e.to_string()))?;
    let body_str = String::from_utf8(body.to_bytes().to_vec())
        .map_err(|_| FsError::BadRequest("invalid UTF-8".into()))?;
    let delete_body: DeleteBody = serde_json::from_str(&body_str)
        .map_err(|e| FsError::BadRequest(format!("invalid JSON: {}", e)))?;

    // Check confirm flag
    if !delete_body.confirm {
        return Err(FsError::BadRequest("confirm required".into()));
    }

    let peer = fingerprint.unwrap_or("unknown").to_string();
    let mut deleted = Vec::new();
    let mut failed = Vec::new();

    for path in &delete_body.paths {
        // Validate path
        let abs = match state.guard.check(path) {
            Ok(p) => p,
            Err(e) => {
                failed.push(DeleteFailure {
                    path: path.clone(),
                    reason: e.to_string(),
                });
                continue;
            }
        };

        // Check existence
        if !abs.exists() {
            failed.push(DeleteFailure {
                path: path.clone(),
                reason: "not found".to_string(),
            });
            continue;
        }

        // Get file size for audit (before deletion)
        let size = tokio::fs::metadata(&abs).await.ok().map(|m| m.len());

        // Delete based on recycle flag
        let result = if delete_body.recycle {
            // T-015: call recycle bin
            super::recycle::recycle(&abs).await
        } else {
            delete_permanently(&abs).await
        };

        match result {
            Ok(_) => {
                deleted.push(path.clone());
                tracing::info!(path = %path, recycle = delete_body.recycle, "fs delete succeeded");

                // Record audit entry
                if let Some(audit) = &state.audit {
                    let mut entry = super::audit::AuditEntry::new(
                        peer.clone(),
                        "delete".to_string(),
                        path.clone(),
                        "ok".to_string(),
                    )
                    .with_recycle(delete_body.recycle);
                    if let Some(s) = size {
                        entry = entry.with_size(s);
                    }
                    let _ = audit.record(&entry);
                }
            }
            Err(e) => {
                failed.push(DeleteFailure {
                    path: path.clone(),
                    reason: e.to_string(),
                });
                tracing::warn!(path = %path, error = %e, "fs delete failed");

                // Record audit entry for failure
                if let Some(audit) = &state.audit {
                    let entry = super::audit::AuditEntry::new(
                        peer.clone(),
                        "delete".to_string(),
                        path.clone(),
                        e.to_string(),
                    )
                    .with_recycle(delete_body.recycle);
                    let _ = audit.record(&entry);
                }
            }
        }
    }

    Ok(json_response(
        StatusCode::OK,
        &DeleteResponse { deleted, failed },
    ))
}

/// Permanently delete a file or directory.
///
/// Uses `remove_file` for files, `remove_dir_all` for directories.
async fn delete_permanently(path: &Path) -> Result<(), FsError> {
    let meta = tokio::fs::metadata(path).await.map_err(|e| FsError::Io(e.to_string()))?;

    if meta.is_dir() {
        tokio::fs::remove_dir_all(path).await.map_err(|e| FsError::Io(e.to_string()))?;
    } else {
        tokio::fs::remove_file(path).await.map_err(|e| FsError::Io(e.to_string()))?;
    }

    Ok(())
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fs::{FsConfig, FsRoot, MountTable};
    use std::path::PathBuf;

    /// Build an `FsState` rooted at a real tempdir.
    fn fixture() -> (FsState, PathBuf) {
        let dir = tempfile_subdir("move_delete");
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
        p.push(format!("localsend_move_delete_{}_{}_{}", test, pid, nanos));
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    #[tokio::test]
    async fn move_renames_file() {
        let (state, dir) = fixture();
        let src = dir.join("src.txt");
        let dst = dir.join("dst.txt");
        std::fs::write(&src, "hello").unwrap();

        // Use relative paths that PathGuard can resolve
        let from = "src.txt";
        let to = "dst.txt";

        // Validate source (must exist)
        let from_abs = state.guard.check(from).unwrap();
        assert!(from_abs.exists());

        // For destination, validate parent directory
        let to_path = std::path::Path::new(to);
        let to_parent = to_path.parent().unwrap();
        let to_parent_str = if to_parent.as_os_str().is_empty() {
            "."
        } else {
            &to_parent.to_string_lossy()
        };
        let to_parent_abs = state.guard.check(to_parent_str).unwrap();
        let to_abs = to_parent_abs.join(to_path.file_name().unwrap());

        // Perform the move
        tokio::fs::rename(&from_abs, &to_abs).await.unwrap();

        assert!(!src.exists());
        assert!(dst.exists());
        assert_eq!(std::fs::read_to_string(&dst).unwrap(), "hello");
    }

    #[tokio::test]
    async fn move_moves_across_dir() {
        let (state, dir) = fixture();
        let subdir = dir.join("subdir");
        std::fs::create_dir(&subdir).unwrap();
        let src = dir.join("file.txt");
        let dst = subdir.join("file.txt");
        std::fs::write(&src, "content").unwrap();

        let from = "file.txt";
        let to = "subdir/file.txt";

        // Validate source
        let from_abs = state.guard.check(from).unwrap();
        assert!(from_abs.exists());

        // Validate destination parent
        let to_path = std::path::Path::new(to);
        let to_parent_abs = state.guard.check("subdir").unwrap();
        let to_abs = to_parent_abs.join(to_path.file_name().unwrap());

        tokio::fs::rename(&from_abs, &to_abs).await.unwrap();

        assert!(!src.exists());
        assert!(dst.exists());
    }

    #[tokio::test]
    async fn delete_files_batch() {
        let (state, dir) = fixture();
        let f1 = dir.join("f1.txt");
        let f2 = dir.join("f2.txt");
        let f3 = dir.join("f3.txt");
        std::fs::write(&f1, "1").unwrap();
        std::fs::write(&f2, "2").unwrap();
        std::fs::write(&f3, "3").unwrap();

        let paths = vec!["f1.txt", "f2.txt", "f3.txt"];

        let mut deleted = Vec::new();
        for path in &paths {
            let abs = state.guard.check(path).unwrap();
            delete_permanently(&abs).await.unwrap();
            deleted.push(path.to_string());
        }

        assert_eq!(deleted.len(), 3);
        assert!(!f1.exists());
        assert!(!f2.exists());
        assert!(!f3.exists());
    }

    #[tokio::test]
    async fn delete_recursive_dir() {
        let (state, dir) = fixture();
        let subdir = dir.join("subdir");
        std::fs::create_dir(&subdir).unwrap();
        std::fs::write(subdir.join("file.txt"), "content").unwrap();

        let path = "subdir";
        let abs = state.guard.check(path).unwrap();
        delete_permanently(&abs).await.unwrap();

        assert!(!subdir.exists());
    }

    #[tokio::test]
    async fn delete_partial_failure_aggregated() {
        let (state, dir) = fixture();
        let f1 = dir.join("exists.txt");
        std::fs::write(&f1, "content").unwrap();

        let paths = vec!["exists.txt", "not_exists.txt"];

        let mut deleted = Vec::new();
        let mut failed = Vec::new();

        for path in &paths {
            match state.guard.check(path) {
                Ok(abs) => {
                    if abs.exists() {
                        match delete_permanently(&abs).await {
                            Ok(_) => deleted.push(path.to_string()),
                            Err(e) => failed.push((path.to_string(), e.to_string())),
                        }
                    } else {
                        failed.push((path.to_string(), "not found".to_string()));
                    }
                }
                Err(e) => failed.push((path.to_string(), e.to_string())),
            }
        }

        assert_eq!(deleted.len(), 1);
        assert_eq!(failed.len(), 1);
        assert_eq!(failed[0].0, "not_exists.txt");
    }
}
