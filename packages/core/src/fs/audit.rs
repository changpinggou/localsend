//! Audit logging for the `fs` module (T-015).
//!
//! Records every write operation (mkdir, upload, move, delete) to a JSONL
//! file for compliance and debugging. The log rotates daily at midnight and
//! retains entries for 7 days.
//!
//! ## Wire format
//!
//! Each line is a JSON object:
//! ```json
//! {
//!   "ts": 1756800000,
//!   "peer": "AB12CD34...",
//!   "op": "delete",
//!   "path": "D:/tmp/old.txt",
//!   "result": "ok",
//!   "size": 12345,
//!   "recycle": false
//! }
//! ```
//!
//! ## Storage
//!
//! The log file lives at `<config_dir>/audit.jsonl`. Rotated files are
//! named `audit.jsonl.<YYYY-MM-DD>` and deleted after 7 days.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use chrono::{DateTime, Local, TimeZone, Utc};
use serde::{Deserialize, Serialize};

use super::path::FsError;

// =====================================================================
// AuditEntry
// =====================================================================

/// A single audit log entry. Serialized as one JSON line per entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    /// Unix epoch seconds when the operation occurred.
    pub ts: i64,
    /// Fingerprint of the peer that initiated the operation.
    pub peer: String,
    /// Operation type: "mkdir", "upload", "delete", "move".
    pub op: String,
    /// Path affected (relative to whitelist root).
    pub path: String,
    /// Result: "ok" or an error code.
    pub result: String,
    /// File size in bytes (if applicable).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
    /// Whether the delete operation used the recycle bin (T-015).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recycle: Option<bool>,
}

impl AuditEntry {
    /// Create a new audit entry with the current timestamp.
    pub fn new(peer: String, op: String, path: String, result: String) -> Self {
        Self {
            ts: Utc::now().timestamp(),
            peer,
            op,
            path,
            result,
            size: None,
            recycle: None,
        }
    }

    /// Attach a file size to this entry.
    pub fn with_size(mut self, size: u64) -> Self {
        self.size = Some(size);
        self
    }

    /// Attach a recycle bin flag to this entry.
    pub fn with_recycle(mut self, recycle: bool) -> Self {
        self.recycle = Some(recycle);
        self
    }
}

// =====================================================================
// AuditLog
// =====================================================================

/// Manages the audit log file: append, query, rotate.
///
/// The log file is opened in append mode and locked with a `Mutex` to
/// serialize writes from multiple concurrent requests. Rotation is
/// triggered by [`rotate_if_needed`](Self::rotate_if_needed), which
/// should be called periodically (e.g., at server startup and after
/// each write).
pub struct AuditLog {
    /// Path to the active log file (e.g., `~/.local/share/localsend/audit.jsonl`).
    path: PathBuf,
    /// Mutex to serialize append operations.
    lock: Mutex<()>,
}

impl AuditLog {
    /// Create a new audit logger.
    ///
    /// The `config_dir` is the directory where the log file will be stored.
    /// It must exist; if it doesn't, the caller should create it first.
    pub fn new(config_dir: &Path) -> Result<Self, FsError> {
        let path = config_dir.join("audit.jsonl");
        Ok(Self {
            path,
            lock: Mutex::new(()),
        })
    }

    /// Record an audit entry by appending it to the log file.
    ///
    /// The entry is serialized as a single JSON line followed by a newline.
    /// If the file doesn't exist, it's created. If the write fails, the
    /// error is logged but not propagated (audit failures should not block
    /// the main operation).
    pub fn record(&self, entry: &AuditEntry) -> Result<(), FsError> {
        let _guard = self.lock.lock().map_err(|e| FsError::Io(e.to_string()))?;

        // Serialize the entry as a single JSON line
        let json = serde_json::to_string(entry).map_err(|e| FsError::Io(e.to_string()))?;
        let line = format!("{}\n", json);

        // Open the file in append mode and write the line
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)
            .map_err(|e| FsError::Io(e.to_string()))?;

        use std::io::Write;
        file.write_all(line.as_bytes())
            .map_err(|e| FsError::Io(e.to_string()))?;

        Ok(())
    }

    /// Query audit entries within a time range.
    ///
    /// Returns all entries with `ts >= since` and optionally filtered by
    /// `peer`. The results are sorted by timestamp (oldest first).
    ///
    /// This is a linear scan of the log file. For large logs, consider
    /// indexing by timestamp (future work).
    pub fn query(
        &self,
        since: DateTime<Utc>,
        peer: Option<&str>,
    ) -> Result<Vec<AuditEntry>, FsError> {
        let _guard = self.lock.lock().map_err(|e| FsError::Io(e.to_string()))?;

        let file = match std::fs::File::open(&self.path) {
            Ok(f) => f,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                return Ok(Vec::new());
            }
            Err(e) => return Err(FsError::Io(e.to_string())),
        };

        let reader = std::io::BufReader::new(file);
        let mut entries = Vec::new();

        for line in std::io::BufRead::lines(reader) {
            let line = line.map_err(|e| FsError::Io(e.to_string()))?;
            if line.trim().is_empty() {
                continue;
            }

            match serde_json::from_str::<AuditEntry>(&line) {
                Ok(entry) => {
                    let entry_ts = DateTime::<Utc>::from_timestamp(entry.ts, 0)
                        .unwrap_or_else(|| Utc::now());
                    if entry_ts >= since {
                        if let Some(peer_filter) = peer {
                            if entry.peer != peer_filter {
                                continue;
                            }
                        }
                        entries.push(entry);
                    }
                }
                Err(_) => {
                    // Skip malformed lines (corruption, partial writes)
                    continue;
                }
            }
        }

        entries.sort_by_key(|e| e.ts);
        Ok(entries)
    }

    /// Rotate the log file if it's older than today.
    ///
    /// The current log file is renamed to `audit.jsonl.<YYYY-MM-DD>` and
    /// a new empty file is created. Old rotated files (older than 7 days)
    /// are deleted.
    ///
    /// This should be called at server startup and periodically (e.g.,
    /// daily at midnight).
    pub fn rotate_if_needed(&self) -> Result<(), FsError> {
        let _guard = self.lock.lock().map_err(|e| FsError::Io(e.to_string()))?;

        // Check if the current log file exists
        if !self.path.exists() {
            return Ok(());
        }

        // Get the file's modification time
        let metadata = std::fs::metadata(&self.path).map_err(|e| FsError::Io(e.to_string()))?;
        let modified = metadata.modified().map_err(|e| FsError::Io(e.to_string()))?;
        let modified_local: DateTime<Local> = modified.into();
        let today = Local::now();

        // If the file was modified today, no rotation needed
        if modified_local.date_naive() == today.date_naive() {
            return Ok(());
        }

        // Rotate: rename the current file to audit.jsonl.<YYYY-MM-DD>
        let date_str = modified_local.format("%Y-%m-%d").to_string();
        let rotated_path = self.path.with_extension(format!("jsonl.{}", date_str));

        std::fs::rename(&self.path, &rotated_path).map_err(|e| FsError::Io(e.to_string()))?;

        // Create a new empty log file
        std::fs::File::create(&self.path).map_err(|e| FsError::Io(e.to_string()))?;

        // Clean up old rotated files (older than 7 days)
        self.cleanup_old_rotations()?;

        Ok(())
    }

    /// Delete rotated log files older than 7 days.
    fn cleanup_old_rotations(&self) -> Result<(), FsError> {
        let parent = self.path.parent().ok_or_else(|| FsError::Io("no parent dir".into()))?;
        let prefix = self.path.file_name().ok_or_else(|| FsError::Io("no filename".into()))?;
        let prefix_str = prefix.to_string_lossy();

        let today = Local::now();
        let cutoff = today - chrono::Duration::days(7);

        let entries = std::fs::read_dir(parent).map_err(|e| FsError::Io(e.to_string()))?;

        for entry in entries {
            let entry = entry.map_err(|e| FsError::Io(e.to_string()))?;
            let name = entry.file_name();
            let name_str = name.to_string_lossy();

            // Match files like "audit.jsonl.2026-09-22"
            if !name_str.starts_with(&format!("{}.", prefix_str)) {
                continue;
            }

            // Extract the date part
            let date_part = match name_str.strip_prefix(&format!("{}.", prefix_str)) {
                Some(d) => d,
                None => continue,
            };

            // Parse the date
            let file_date = match chrono::NaiveDate::parse_from_str(date_part, "%Y-%m-%d") {
                Ok(d) => d,
                Err(_) => continue,
            };

            // Check if older than cutoff
            let file_datetime = file_date.and_hms_opt(0, 0, 0).unwrap();
            let file_local = Local.from_utc_datetime(&file_datetime);
            if file_local < cutoff {
                let _ = std::fs::remove_file(entry.path());
            }
        }

        Ok(())
    }

    /// Get the path to the active log file.
    pub fn path(&self) -> &Path {
        &self.path
    }
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_config_dir() -> PathBuf {
        let mut p = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!("localsend_audit_{}_{}", pid, nanos));
        fs::create_dir_all(&p).unwrap();
        p
    }

    #[test]
    fn audit_writes_jsonl_line() {
        let dir = temp_config_dir();
        let log = AuditLog::new(&dir).unwrap();

        let entry = AuditEntry::new(
            "PEER123".into(),
            "delete".into(),
            "Photos/old.txt".into(),
            "ok".into(),
        )
        .with_size(12345);

        log.record(&entry).unwrap();

        // Read the file and verify the JSON line
        let content = fs::read_to_string(log.path()).unwrap();
        let parsed: AuditEntry = serde_json::from_str(content.trim()).unwrap();

        assert_eq!(parsed.peer, "PEER123");
        assert_eq!(parsed.op, "delete");
        assert_eq!(parsed.path, "Photos/old.txt");
        assert_eq!(parsed.result, "ok");
        assert_eq!(parsed.size, Some(12345));

        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn audit_query_filters_by_since() {
        let dir = temp_config_dir();
        let log = AuditLog::new(&dir).unwrap();

        // Write 3 entries with different timestamps
        let now = Utc::now();
        let old_entry = AuditEntry {
            ts: (now - chrono::Duration::days(2)).timestamp(),
            peer: "PEER1".into(),
            op: "upload".into(),
            path: "file1.txt".into(),
            result: "ok".into(),
            size: None,
            recycle: None,
        };
        let recent_entry = AuditEntry {
            ts: (now - chrono::Duration::hours(1)).timestamp(),
            peer: "PEER2".into(),
            op: "delete".into(),
            path: "file2.txt".into(),
            result: "ok".into(),
            size: None,
            recycle: None,
        };
        let new_entry = AuditEntry {
            ts: now.timestamp(),
            peer: "PEER1".into(),
            op: "move".into(),
            path: "file3.txt".into(),
            result: "ok".into(),
            size: None,
            recycle: None,
        };

        log.record(&old_entry).unwrap();
        log.record(&recent_entry).unwrap();
        log.record(&new_entry).unwrap();

        // Query entries from the last day
        let since = now - chrono::Duration::days(1);
        let results = log.query(since, None).unwrap();

        assert_eq!(results.len(), 2);
        assert_eq!(results[0].path, "file2.txt");
        assert_eq!(results[1].path, "file3.txt");

        // Query with peer filter
        let results = log.query(since, Some("PEER1")).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].path, "file3.txt");

        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn audit_rotate_drops_old_files() {
        let dir = temp_config_dir();
        let log = AuditLog::new(&dir).unwrap();

        // Create a fake old rotated file (8 days ago)
        let old_date = (Local::now() - chrono::Duration::days(8)).format("%Y-%m-%d").to_string();
        let old_file = dir.join(format!("audit.jsonl.{}", old_date));
        fs::write(&old_file, "old data").unwrap();

        // Create a recent rotated file (3 days ago)
        let recent_date = (Local::now() - chrono::Duration::days(3)).format("%Y-%m-%d").to_string();
        let recent_file = dir.join(format!("audit.jsonl.{}", recent_date));
        fs::write(&recent_file, "recent data").unwrap();

        // Create the active log file with old modification time
        let active_file = log.path();
        fs::write(active_file, "active data").unwrap();

        // Set the modification time to yesterday
        let yesterday = (Local::now() - chrono::Duration::days(1)).timestamp();
        filetime::set_file_mtime(
            active_file,
            filetime::FileTime::from_unix_time(yesterday, 0),
        )
        .unwrap();

        // Rotate
        log.rotate_if_needed().unwrap();

        // The old file should be deleted
        assert!(!old_file.exists());

        // The recent file should still exist
        assert!(recent_file.exists());

        // The active file should be renamed
        let yesterday_date = (Local::now() - chrono::Duration::days(1)).format("%Y-%m-%d").to_string();
        let rotated_file = dir.join(format!("audit.jsonl.{}", yesterday_date));
        assert!(rotated_file.exists());

        // A new active file should be created
        assert!(active_file.exists());

        fs::remove_dir_all(&dir).unwrap();
    }
}
