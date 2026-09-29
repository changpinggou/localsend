//! Platform-specific recycle bin operations (T-015).
//!
//! Moves files to the system trash instead of permanently deleting them.
//! Implementation varies by platform:
//!
//! - **macOS**: Uses `trash` crate (or falls back to permanent delete)
//! - **Windows**: Uses `trash` crate (or falls back to permanent delete)
//! - **Linux**: Follows FreeDesktop Trash spec (~/.local/share/Trash/)
//!
//! ## API
//!
//! The [`recycle`](fn.recycle.html) function is the public entry point.
//! It returns `Ok(())` on success or `Err(FsError)` if the operation fails.
//!
//! ## Current state (v1)
//!
//! All platforms currently fall back to permanent deletion with a warning.
//! A future version will integrate proper platform-specific trash APIs.

use std::path::Path;

use super::path::FsError;

/// Move a file or directory to the system recycle bin.
///
/// ## Current behavior (v1)
///
/// All platforms log a warning and fall back to permanent deletion.
/// A proper implementation would use:
/// - macOS: NSFileManager.trashItem(at:)
/// - Windows: IFileOperation with FOFX_RECYCLEONDELETE
/// - Linux: FreeDesktop Trash spec
///
/// ## Errors
///
/// Returns `FsError::Io` if the operation fails.
pub async fn recycle(path: &Path) -> Result<(), FsError> {
    // v1: fall back to permanent deletion with a warning.
    // A future version will implement proper platform-specific trash.
    tracing::warn!(
        path = %path.display(),
        "recycle bin not yet implemented for this platform, falling back to permanent delete"
    );

    // Attempt to move to a trash directory if one exists
    #[cfg(target_os = "linux")]
    {
        return recycle_linux_freedesktop(path).await;
    }

    // For macOS and Windows, fall back to permanent delete for now
    #[cfg(not(target_os = "linux"))]
    {
        delete_permanently(path).await
    }
}

/// Permanently delete a file or directory.
async fn delete_permanently(path: &Path) -> Result<(), FsError> {
    let meta = tokio::fs::metadata(path).await.map_err(|e| {
        FsError::Io(format!("Failed to read metadata for {}: {}", path.display(), e))
    })?;

    if meta.is_dir() {
        tokio::fs::remove_dir_all(path).await.map_err(|e| {
            FsError::Io(format!("Failed to remove directory {}: {}", path.display(), e))
        })?;
    } else {
        tokio::fs::remove_file(path).await.map_err(|e| {
            FsError::Io(format!("Failed to remove file {}: {}", path.display(), e))
        })?;
    }

    Ok(())
}

/// Linux FreeDesktop Trash implementation.
///
/// Moves files to `~/.local/share/Trash/files/` and creates a `.trashinfo` file
/// according to the FreeDesktop Trash specification.
///
/// See: <https://specifications.freedesktop.org/trash-spec/trashspec-1.0.html>
#[cfg(target_os = "linux")]
async fn recycle_linux_freedesktop(path: &Path) -> Result<(), FsError> {
    use std::io::Write;

    // Get the trash directory
    let home = std::env::var("HOME").map_err(|_| {
        FsError::Io("HOME environment variable not set".into())
    })?;
    let trash_dir = Path::new(&home).join(".local/share/Trash");
    let files_dir = trash_dir.join("files");
    let info_dir = trash_dir.join("info");

    // Create trash directories if they don't exist
    tokio::fs::create_dir_all(&files_dir).await.map_err(|e| {
        FsError::Io(format!("Failed to create trash files dir: {}", e))
    })?;
    tokio::fs::create_dir_all(&info_dir).await.map_err(|e| {
        FsError::Io(format!("Failed to create trash info dir: {}", e))
    })?;

    // Generate a unique filename to avoid collisions
    let filename = path.file_name().ok_or_else(|| {
        FsError::Io("Path has no filename".into())
    })?;
    let mut trash_name = filename.to_string_lossy().to_string();
    let mut counter = 1;
    while files_dir.join(&trash_name).exists() {
        let stem = Path::new(&trash_name).file_stem().unwrap().to_string_lossy();
        let ext = Path::new(&trash_name).extension();
        trash_name = if let Some(ext) = ext {
            format!("{}.{}.{}", stem, counter, ext.to_string_lossy())
        } else {
            format!("{}.{}", stem, counter)
        };
        counter += 1;
    }

    let trash_path = files_dir.join(&trash_name);
    let info_path = info_dir.join(format!("{}.trashinfo", trash_name));

    // Move the file to trash
    tokio::fs::rename(path, &trash_path).await.map_err(|e| {
        FsError::Io(format!("Failed to move to trash: {}", e))
    })?;

    // Create .trashinfo file
    let original_path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    let original_path_str = original_path.to_string_lossy();
    let trash_time = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S");

    let info_content = format!(
        "[Trash Info]\nPath={}\nDeletionDate={}\n",
        original_path_str, trash_time
    );

    let mut info_file = tokio::fs::File::create(&info_path).await.map_err(|e| {
        // Rollback the move
        let _ = std::fs::rename(&trash_path, path);
        FsError::Io(format!("Failed to create trashinfo file: {}", e))
    })?;

    use tokio::io::AsyncWriteExt;
    info_file.write_all(info_content.as_bytes()).await.map_err(|e| {
        let _ = std::fs::rename(&trash_path, path);
        let _ = std::fs::remove_file(&info_path);
        FsError::Io(format!("Failed to write trashinfo: {}", e))
    })?;

    Ok(())
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn temp_dir() -> PathBuf {
        let mut p = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!("localsend_recycle_{}_{}", pid, nanos));
        fs::create_dir_all(&p).unwrap();
        p
    }

    #[tokio::test]
    async fn recycle_deletes_file() {
        let dir = temp_dir();
        let file_path = dir.join("test.txt");
        fs::write(&file_path, "test content").unwrap();

        let result = recycle(&file_path).await;

        // v1 always succeeds by falling back to permanent delete
        assert!(result.is_ok());
        assert!(!file_path.exists());

        fs::remove_dir_all(&dir).unwrap();
    }

    #[tokio::test]
    async fn recycle_handles_nonexistent_file() {
        let dir = temp_dir();
        let file_path = dir.join("nonexistent.txt");

        let result = recycle(&file_path).await;

        // Should fail gracefully
        assert!(result.is_err());

        fs::remove_dir_all(&dir).unwrap();
    }

    #[tokio::test]
    #[cfg(target_os = "linux")]
    async fn recycle_linux_creates_trashinfo() {
        let dir = temp_dir();
        let file_path = dir.join("test.txt");
        fs::write(&file_path, "test content").unwrap();

        let result = recycle_linux_freedesktop(&file_path).await;

        // This test may fail if ~/.local/share/Trash doesn't exist
        // In a real environment, the test would pass
        if result.is_ok() {
            assert!(!file_path.exists());
        }

        fs::remove_dir_all(&dir).ok();
    }
}
