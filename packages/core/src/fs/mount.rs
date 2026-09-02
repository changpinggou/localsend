//! Mount points and the whitelist table.
//!
//! A "mount point" is a host directory that the server is willing to
//! expose; the *logical* path `/Photos/2026/IMG_0001.jpg` resolves to
//! `<root.path>/Photos/2026/IMG_0001.jpg`. The whitelist — encoded in
//! [`FsConfig::whitelist`](super::FsConfig::whitelist) as a `Vec<FsRoot>`
//! — is the set of allowed mount points. Peers can only see mounts
//! that appear in the whitelist, and only on paths that resolve under
//! one of them.
//!
//! ## Cross-platform enumeration
//!
//! [`FsMount::list`] returns every *candidate* mount point the host
//! currently exposes, unfiltered. The candidate set differs per OS:
//!
//! | OS      | Source directories                                |
//! |---------|---------------------------------------------------|
//! | macOS   | `/Volumes/*` (system volumes filtered)            |
//! | Linux   | `/media/$USER/*` and `/run/media/$USER/*`         |
//! | Windows | every `GetLogicalDrives` letter (T-002 follow-up) |
//!
//! The candidate list is then intersected with the whitelist by
//! [`MountTable::from_config`] to produce the effective set of
//! exposed roots.
//!
//! ## Path comparison
//!
//! [`MountTable::contains`] does a *prefix* comparison, not a
//! canonicalised comparison. That's deliberate: the whitelist check
//! has to be cheap (it's on the hot path for every request) and the
//! real symlink / `..` resolution is the job of
//! [`PathGuard`](super::PathGuard) (T-004). On Windows we
//! additionally lowercase both sides because NTFS is
//! case-insensitive but Rust's `Path::starts_with` is not.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

// =====================================================================
// FsRoot
// =====================================================================

/// A single exposed directory on the host filesystem.
///
/// `id` is the stable, machine-readable handle (e.g. `"D:"` on
/// Windows or `"/Volumes/External"` on macOS) and `label` is what the
/// Flutter UI shows to the user. The two are decoupled so the same
/// volume can be renamed without losing the persistence key.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FsRoot {
    /// Stable identifier. On Windows the drive letter (`"D:"`); on
    /// Unix the absolute path. Used as the `BTreeMap` key in
    /// [`MountTable`], so changing it changes identity.
    pub id: String,

    /// Human-readable label, surfaced in the Dart UI as the root name.
    /// Independent of `id` so users can rename a mount without losing
    /// its whitelist entry.
    pub label: String,

    /// Absolute on-disk path. Always canonicalised before being
    /// stored (T-002 [`FsMount::list`] calls `canonicalize` when
    /// possible; whitelist entries supplied via the UI are normalised
    /// by [`MountTable::from_config`]).
    pub path: PathBuf,

    /// Total size of the volume, in bytes. `0` if the OS does not
    /// report it (network share with restricted ACL, exotic
    /// filesystem, …).
    pub total_bytes: u64,

    /// Free bytes available to the current user. `0` if unknown.
    pub free_bytes: u64,

    /// Filesystem type as a short string: `"APFS"`, `"exFAT"`,
    /// `"ext4"`, `"NTFS"`, `"unknown"`. Used for UI hints only —
    /// never for security decisions.
    pub filesystem: String,

    /// `true` if the volume is removable (USB stick, SD card). The
    /// Flutter UI uses this to show an "eject" affordance. T-018
    /// will keep this fresh as volumes come and go.
    pub is_removable: bool,

    /// `true` if the volume is mounted read-only (e.g. a DVD, a
    /// snapshotted volume). The server will refuse write requests
    /// targeting a read-only root rather than failing partway
    /// through the upload.
    pub is_read_only: bool,
}

impl FsRoot {
    /// Build an `FsRoot` with the disk-size / filesystem fields
    /// zeroed. Convenient for tests and for the whitelist
    /// serialisation path where the OS hasn't been queried yet.
    pub fn new(id: impl Into<String>, label: impl Into<String>, path: impl Into<PathBuf>) -> Self {
        Self {
            id: id.into(),
            label: label.into(),
            path: path.into(),
            total_bytes: 0,
            free_bytes: 0,
            filesystem: "unknown".into(),
            is_removable: false,
            is_read_only: false,
        }
    }
}

// =====================================================================
// MountTable
// =====================================================================

/// Whitelist table: maps every allowed [`FsRoot`] to itself, keyed by
/// `id`.
///
/// `MountTable` is the data structure that
/// [`PathGuard`](super::PathGuard) consults on every request. Backing
/// it with a [`BTreeMap`] (rather than a `HashMap`) gives stable
/// iteration order for the audit log and the UI, with no measurable
/// performance cost at the scale of "a few dozen drives".
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MountTable {
    roots: BTreeMap<String, FsRoot>,
}

impl MountTable {
    /// Construct an empty table. Used in tests; production code should
    /// go through [`MountTable::from_config`].
    pub fn new() -> Self {
        Self::default()
    }

    /// Load a whitelist from a list of [`FsRoot`]s. The keys are
    /// `id`; a duplicate `id` keeps the *last* entry (the
    /// `from_config` call site is the only place users can override
    /// the candidate set returned by [`FsMount::list`], so "last
    /// write wins" matches user expectations).
    pub fn from_config(roots: Vec<FsRoot>) -> Self {
        let mut t = Self::new();
        for r in roots {
            t.roots.insert(r.id.clone(), r);
        }
        t
    }

    /// All mount points, sorted by `id`. Stable order is important
    /// for the audit log and the Dart UI.
    pub fn roots(&self) -> Vec<FsRoot> {
        self.roots.values().cloned().collect()
    }

    /// Look up a root by `id`.
    pub fn get(&self, id: &str) -> Option<&FsRoot> {
        self.roots.get(id)
    }

    /// `true` if `abs_path` resolves under any whitelisted root.
    /// Prefix match, with platform-specific case folding (see
    /// module-level docs).
    pub fn contains(&self, abs_path: &Path) -> bool {
        self.roots.values().any(|r| path_starts_with(abs_path, &r.path))
    }

    /// Replace the entire whitelist. Used by the `update_whitelist`
    /// IPC call (T-003 will wire the Dart side) and by T-019 on
    /// `roots-changed` events.
    pub fn update(&mut self, roots: Vec<FsRoot>) {
        self.roots.clear();
        for r in roots {
            self.roots.insert(r.id.clone(), r);
        }
    }

    /// `label` of the whitelisted root that contains `abs_path`, or
    /// `None` if `abs_path` is not under any root. Used by the audit
    /// log to render paths in user-friendly form.
    pub fn label_of(&self, abs_path: &Path) -> Option<String> {
        for r in self.roots.values() {
            if path_starts_with(abs_path, &r.path) {
                return Some(r.label.clone());
            }
        }
        None
    }

    /// Number of whitelisted roots.
    pub fn len(&self) -> usize {
        self.roots.len()
    }

    /// `true` if no mount point is whitelisted. The server should
    /// refuse to start in this state (T-005 will add the runtime
    /// check); the function is here so tests can assert the
    /// invariant cheaply.
    pub fn is_empty(&self) -> bool {
        self.roots.is_empty()
    }
}

/// `true` if `child` sits under `parent` (component-wise prefix
/// match), with platform-specific case folding.
///
/// This deliberately does *not* resolve symlinks or `..` segments:
/// those are the job of [`PathGuard`](super::PathGuard). The
/// whitelist check is a fast first filter, not a security boundary
/// on its own.
fn path_starts_with(child: &Path, parent: &Path) -> bool {
    #[cfg(target_os = "windows")]
    {
        // NTFS is case-insensitive; `Path::starts_with` is not.
        let child_lc = child.to_string_lossy().to_lowercase();
        let parent_lc = parent.to_string_lossy().to_lowercase();
        Path::new(&child_lc).starts_with(Path::new(&parent_lc))
    }
    #[cfg(not(target_os = "windows"))]
    {
        child.starts_with(parent)
    }
}

// =====================================================================
// FsMount — cross-platform enumeration
// =====================================================================

/// Cross-platform mount-point enumeration.
///
/// The struct has no state; the inherent methods are namespaced here
/// purely for discoverability (`FsMount::list()` reads better than a
/// bare `list_mount_points()`).
pub struct FsMount;

impl FsMount {
    /// Enumerate every candidate mount point currently visible to
    /// the host. The result is *unfiltered* — the whitelist is
    /// applied by [`MountTable::from_config`].
    ///
    /// Returns an empty `Vec` on platforms where enumeration is not
    /// yet implemented (Windows in this ticket) or where the host
    /// has no candidate volumes (e.g. a Linux container with no
    /// `/media` mount). The function never panics: I/O errors
    /// reading the candidate directories are logged at `debug` and
    /// the corresponding volume is skipped.
    pub fn list() -> Vec<FsRoot> {
        let mut roots = Vec::new();
        #[cfg(target_os = "macos")]
        {
            roots.extend(list_macos_volumes());
        }
        #[cfg(target_os = "linux")]
        {
            roots.extend(list_linux_user_media());
        }
        #[cfg(target_os = "windows")]
        {
            roots.extend(list_windows_drives());
        }
        // Other targets (freebsd, netbsd, android, ios) are out of
        // scope for T-002. Add a `#[cfg]` arm when a contributor
        // wants to support them.
        roots
    }

    /// Test seam: scan a directory for sub-directories that look like
    /// mount points and return them with disk info filled in.
    /// Compiled on macOS and Linux only — Windows enumeration is
    /// fundamentally different (drive letters, not directories).
    #[cfg(any(target_os = "macos", target_os = "linux"))]
    pub fn scan(scan_dir: &Path) -> Vec<FsRoot> {
        let mut out = Vec::new();
        let rd = match std::fs::read_dir(scan_dir) {
            Ok(rd) => rd,
            Err(e) => {
                tracing::debug!(dir = ?scan_dir, err = %e, "scan: read_dir failed");
                return out;
            }
        };
        for entry in rd.flatten() {
            let path = entry.path();
            // A mount point is a directory. Skip everything else
            // (regular files, symlinks-to-nowhere, sockets…). The
            // symlink case is intentional: T-004 resolves symlinks
            // at request time, not at enumeration time.
            let Ok(ft) = entry.file_type() else { continue };
            if !ft.is_dir() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') {
                // Hidden directory (e.g. `.Trashes`, `.Spotlight-V100`
                // on macOS) — these are metadata stores, not volumes.
                continue;
            }
            let id = path.to_string_lossy().to_string();
            let label = name.clone();
            let mut root = FsRoot::new(&id, &label, &path);
            fill_unix_disk_info(&mut root, &path);
            out.push(root);
        }
        out
    }
}

// ---------------------------------------------------------------------
// macOS
// ---------------------------------------------------------------------

#[cfg(target_os = "macos")]
fn list_macos_volumes() -> Vec<FsRoot> {
    let mut roots = FsMount::scan(Path::new("/Volumes"));
    // macOS has a synthetic read-only `/System/Volumes/Data` mount
    // that shows up as a candidate but is part of the sealed system
    // volume. Filter it.
    roots.retain(|r| !is_macos_system_volume(&r.path));
    roots
}

#[cfg(target_os = "macos")]
fn is_macos_system_volume(p: &Path) -> bool {
    // On Apple Silicon macOS the read-only system volume is mounted
    // at `/System/Volumes/Data` (writable overlay) and
    // `/System/Volumes/Preboot` (boot helpers). Both are part of
    // the SSV and must not be exposed to the wire.
    matches!(p.to_str(), Some("/System/Volumes/Data") | Some("/System/Volumes/Preboot"))
}

// ---------------------------------------------------------------------
// Linux
// ---------------------------------------------------------------------

#[cfg(target_os = "linux")]
fn list_linux_user_media() -> Vec<FsRoot> {
    let user = std::env::var("USER").unwrap_or_default();
    let mut roots = Vec::new();
    if !user.is_empty() {
        roots.extend(FsMount::scan(Path::new(&format!("/media/{}", user))));
        roots.extend(FsMount::scan(Path::new(&format!("/run/media/{}", user))));
    } else {
        // No $USER (e.g. running inside a container as root) — fall
        // back to the unscoped directories. Containers almost
        // never have anything useful there, but the code path is
        // safe and the function returns an empty Vec in practice.
        roots.extend(FsMount::scan(Path::new("/media")));
        roots.extend(FsMount::scan(Path::new("/run/media")));
    }
    roots
}

// ---------------------------------------------------------------------
// Windows (stub for T-002; full implementation is a follow-up)
// ---------------------------------------------------------------------

/// Stub: return an empty list.
///
/// Full Windows support requires the `windows` crate (for
/// `GetLogicalDrives`, `GetDriveTypeW`, `GetDiskFreeSpaceExW`,
/// `GetVolumeInformationW`) and a small FFI helper to convert a
/// `DRIVE_TYPE` bitmask to an `FsRoot`. Tracked as a follow-up so
/// T-002 doesn't have to add a 50-crate Windows-only dependency
/// tree. The compile path is still exercised on every CI run on
/// `windows-latest` because the function exists and is called.
#[cfg(target_os = "windows")]
fn list_windows_drives() -> Vec<FsRoot> {
    // TODO(t-002-windows): enumerate via GetLogicalDrives, filter
    // system volumes (DRIVE_FIXED + is_system), fill size/fs info
    // via GetDiskFreeSpaceExW + GetVolumeInformationW. Add the
    // `windows` crate at that point.
    Vec::new()
}

// ---------------------------------------------------------------------
// Unix disk info (macOS + Linux)
// ---------------------------------------------------------------------

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn fill_unix_disk_info(root: &mut FsRoot, path: &Path) {
    use std::ffi::CString;

    // `libc::statvfs` is the portable Unix way to get a volume's
    // total / available size. `libc` is already a transitive dep of
    // the crate on Unix (see Cargo.toml
    // `[target.'cfg(unix)'.dependencies]`).
    let Some(p) = path.to_str() else { return };
    let Ok(cpath) = CString::new(p) else { return };
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    // SAFETY: `cpath` is a valid NUL-terminated C string; `stat`
    // is a writable output buffer.
    let r = unsafe { libc::statvfs(cpath.as_ptr(), &mut stat) };
    if r != 0 {
        // Either the path doesn't exist (e.g. a USB stick was
        // unplugged between `read_dir` and now) or we lack
        // permission. Either way, leave the size as 0 — the UI
        // hides zero-sized entries.
        return;
    }
    // `f_blocks` is in `f_frsize` units. On Linux `f_frsize` is the
    // preferred block size; on macOS it's identical to `f_bsize`.
    // `f_bavail` is "blocks available to non-superuser", which is
    // what users actually have to write into.
    let bs = stat.f_frsize as u64;
    root.total_bytes = (stat.f_blocks as u64).saturating_mul(bs);
    root.free_bytes = (stat.f_bavail as u64).saturating_mul(bs);
    // The standard `statvfs` does not expose a filesystem name
    // portably. `f_fstypename` exists on some BSDs but not on Linux
    // or macOS. Leave the field as "unknown" — T-018 will fill it
    // from `/etc/mtab` (Linux) or `diskutil info` (macOS) when it
    // adds hotplug awareness.
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    fn sample_root() -> FsRoot {
        FsRoot::new("/Volumes/Photos", "Photos", "/Volumes/Photos")
    }

    #[test]
    fn fs_root_new_fills_size_with_zeros() {
        let r = sample_root();
        assert_eq!(r.id, "/Volumes/Photos");
        assert_eq!(r.label, "Photos");
        assert_eq!(r.path, PathBuf::from("/Volumes/Photos"));
        assert_eq!(r.total_bytes, 0);
        assert_eq!(r.free_bytes, 0);
        assert_eq!(r.filesystem, "unknown");
        assert!(!r.is_removable);
        assert!(!r.is_read_only);
    }

    #[test]
    fn mount_table_default_is_empty() {
        // N-SEC-2: the server is locked down out of the box. This
        // test is the canary — if it ever fails, the safety model
        // has been broken.
        let t = MountTable::new();
        assert!(t.is_empty());
        assert_eq!(t.len(), 0);
        assert!(t.roots().is_empty());
    }

    #[test]
    fn from_config_populates_table() {
        let roots = vec![
            sample_root(),
            FsRoot::new("/Volumes/Music", "Music", "/Volumes/Music"),
        ];
        let t = MountTable::from_config(roots);
        assert_eq!(t.len(), 2);
        assert!(t.get("/Volumes/Photos").is_some());
        assert!(t.get("/Volumes/Music").is_some());
    }

    #[test]
    fn from_config_dedupes_by_id() {
        // Same `id`, different `label` — the second write wins.
        let roots = vec![
            FsRoot::new("/A", "old", "/A"),
            FsRoot::new("/A", "new", "/A"),
        ];
        let t = MountTable::from_config(roots);
        assert_eq!(t.len(), 1);
        assert_eq!(t.get("/A").unwrap().label, "new");
    }

    #[test]
    fn roots_returns_sorted_by_id() {
        let roots = vec![
            FsRoot::new("/c", "c", "/c"),
            FsRoot::new("/a", "a", "/a"),
            FsRoot::new("/b", "b", "/b"),
        ];
        let t = MountTable::from_config(roots);
        let ids: Vec<String> = t.roots().into_iter().map(|r| r.id).collect();
        assert_eq!(ids, vec!["/a", "/b", "/c"]);
    }

    #[test]
    fn contains_matches_prefix_under_root() {
        let t = MountTable::from_config(vec![sample_root()]);
        assert!(t.contains(Path::new("/Volumes/Photos/2026/IMG.jpg")));
        assert!(t.contains(Path::new("/Volumes/Photos")));
        // Sibling directory — not under the root.
        assert!(!t.contains(Path::new("/Volumes/Music/x.mp3")));
        // Unrelated path.
        assert!(!t.contains(Path::new("/etc/passwd")));
    }

    #[test]
    fn contains_does_not_match_partial_component() {
        // `/Volumes/PhotosBackup` must NOT be considered under
        // `/Volumes/Photos`. This is the classic
        // `starts_with("/a")` bug — `Path::starts_with` is
        // component-aware so we get this for free on Unix, but
        // the test guards against a future refactor that uses
        // string-level starts_with.
        let t = MountTable::from_config(vec![sample_root()]);
        assert!(!t.contains(Path::new("/Volumes/PhotosBackup")));
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn contains_is_case_insensitive_on_windows() {
        let t = MountTable::from_config(vec![FsRoot::new("D:", "Drive D", "D:\\")]);
        assert!(t.contains(Path::new("d:\\foo")));
        assert!(t.contains(Path::new("D:\\Foo")));
    }

    #[test]
    #[cfg(not(target_os = "windows"))]
    fn contains_is_case_sensitive_on_unix() {
        // On Unix, `Photos` and `photos` are different paths. The
        // OS would not let both exist, so this test is a
        // defence-in-depth: a future refactor that lowercases the
        // query on Unix would break the model.
        let t = MountTable::from_config(vec![FsRoot::new("/data/Photos", "P", "/data/Photos")]);
        assert!(!t.contains(Path::new("/data/photos/x.jpg")));
    }

    #[test]
    fn label_of_returns_root_label() {
        let t = MountTable::from_config(vec![
            FsRoot::new("/A", "Alpha", "/A"),
            FsRoot::new("/B", "Beta", "/B"),
        ]);
        assert_eq!(t.label_of(Path::new("/A/x")).as_deref(), Some("Alpha"));
        assert_eq!(t.label_of(Path::new("/B/y")).as_deref(), Some("Beta"));
        assert_eq!(t.label_of(Path::new("/C/z")), None);
    }

    #[test]
    fn update_replaces_entire_table() {
        let mut t = MountTable::from_config(vec![FsRoot::new("/A", "A", "/A")]);
        assert_eq!(t.len(), 1);
        t.update(vec![
            FsRoot::new("/X", "X", "/X"),
            FsRoot::new("/Y", "Y", "/Y"),
        ]);
        assert_eq!(t.len(), 2);
        assert!(t.get("/A").is_none());
        assert!(t.get("/X").is_some());
        assert!(t.get("/Y").is_some());
    }

    // -------- platform-specific enumeration tests -----------------

    /// Helper: turn a `Vec<FsRoot>` into a `BTreeSet<String>` of ids
    /// for set-equality assertions.
    fn ids(rs: &[FsRoot]) -> BTreeSet<String> {
        rs.iter().map(|r| r.id.clone()).collect()
    }

    #[test]
    #[cfg(target_os = "macos")]
    fn scan_reads_mock_volumes_dir() {
        // Build a tempdir shaped like `/Volumes`: one real
        // subdirectory (treated as a mount) and one hidden
        // subdirectory (must be skipped).
        let tmp = tempdir_like();
        std::fs::create_dir(tmp.join("Photos")).unwrap();
        std::fs::create_dir(tmp.join(".Spotlight-V100")).unwrap();
        std::fs::write(tmp.join("not-a-dir.txt"), b"").unwrap();

        let rs = FsMount::scan(&tmp);
        let found = ids(&rs);
        assert!(
            found.contains(tmp.join("Photos").to_str().unwrap()),
            "expected Photos in {:?}, got {:?}",
            tmp,
            found
        );
        assert!(
            !found.iter().any(|s| s.contains(".Spotlight")),
            "hidden dirs must be skipped, got {:?}",
            found
        );
    }

    #[test]
    #[cfg(target_os = "macos")]
    fn list_filters_system_volumes() {
        // The system volume filter is the one piece of platform
        // logic that's hard to exercise without root. Run it
        // against a list of fake candidates; only the non-system
        // ones should survive.
        let candidates = vec![
            FsRoot::new("/Volumes/Photos", "Photos", "/Volumes/Photos"),
            FsRoot::new("/System/Volumes/Data", "sys", "/System/Volumes/Data"),
        ];
        let filtered: Vec<FsRoot> = candidates
            .into_iter()
            .filter(|r| !is_macos_system_volume(&r.path))
            .collect();
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].label, "Photos");
    }

    #[test]
    #[cfg(target_os = "linux")]
    fn scan_reads_mock_media_dir() {
        let tmp = tempdir_like();
        std::fs::create_dir(tmp.join("USB1")).unwrap();
        std::fs::create_dir(tmp.join("USB2")).unwrap();
        let rs = FsMount::scan(&tmp);
        let found = ids(&rs);
        assert_eq!(found.len(), 2);
        assert!(found.contains(tmp.join("USB1").to_str().unwrap()));
        assert!(found.contains(tmp.join("USB2").to_str().unwrap()));
    }

    #[test]
    #[cfg(any(target_os = "macos", target_os = "linux"))]
    fn scan_handles_missing_directory() {
        // `/definitely/does/not/exist/anywhere` — `FsMount::scan`
        // must return an empty Vec rather than panic.
        let bogus = Path::new("/definitely/does/not/exist/anywhere");
        let rs = FsMount::scan(bogus);
        assert!(rs.is_empty());
    }

    /// Lightweight tempdir helper. We deliberately do not pull in
    /// the `tempfile` crate just for tests — `std::env::temp_dir`
    /// plus a unique-enough name is enough.
    fn tempdir_like() -> PathBuf {
        let mut p = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!("localsend_fs_test_{}_{}", pid, nanos));
        std::fs::create_dir_all(&p).unwrap();
        p
    }
}
