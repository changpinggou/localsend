//! Server-side tuning for the LocalU `fs` feature.
//!
//! `FsConfig` is the single source of truth for everything that's tunable
//! from the Flutter side: the mount-point whitelist, the recycle-bin toggle,
//! upload limits, thumbnail limits and list-pagination sizing. It is plain
//! data — no I/O, no platform calls, no async — so it can be deserialised
//! from a JSON config file or built programmatically with [`Default`].
//!
//! The whitelist field carries full [`FsRoot`] records (id + label +
//! path + disk info) rather than bare path strings, so the UI can
//! show "Photos" instead of "/Volumes/Photos" without a second
//! lookup table.

use serde::{Deserialize, Serialize};

use super::mount::FsRoot;

/// Compile-time / config-time tuning for the `fs` module.
///
/// Every field is `pub` for ergonomic deserialisation; the [`Default`]
/// implementation is the single place the values are defined.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FsConfig {
    /// Mount-point whitelist. Empty by default so the server is
    /// locked down out of the box (N-SEC-2). T-002 ships the
    /// [`FsRoot`] structure that backs this; T-003 will provide the
    /// IPC handler that lets the Flutter side populate it.
    pub whitelist: Vec<FsRoot>,

    /// Whether the platform-specific recycle bin / trash should be used
    /// for deletes (Windows / macOS) vs a hard `rm` (Linux / *BSD).
    /// T-015 will wire the actual implementation.
    pub recycle_bin: bool,

    /// Hard upper bound for a single upload, in bytes. T-010 will
    /// enforce this against `Content-Length` and the streaming
    /// `Read` source. Default: 10 GiB.
    pub max_upload_size: u64,

    /// Edge length of generated thumbnails, in pixels. T-021 uses this
    /// to cap the longest side of a downscaled preview. Default: 200 px.
    pub thumbnail_max_dim: u32,

    /// Maximum number of entries returned in a single `list` page.
    /// T-008 will paginate with `?page=N&size=` and clamp to this value
    /// so a malicious peer can't `?size=1000000` us. Default: 200.
    pub max_list_page_size: u32,
}

impl Default for FsConfig {
    fn default() -> Self {
        Self {
            whitelist: Vec::new(),
            recycle_bin: false,
            max_upload_size: 10 * 1024 * 1024 * 1024, // 10 GiB
            thumbnail_max_dim: 200,
            max_list_page_size: 200,
        }
    }
}

impl FsConfig {
    /// Replace the whitelist with `roots`. This is the single
    /// mutation point that the IPC handler (T-003) and the
    /// `roots-changed` event handler (T-019) should use, so the
    /// "update whitelist" path is auditable in one place.
    ///
    /// Duplicate `id`s collapse to the last entry, matching
    /// [`MountTable::from_config`](super::MountTable::from_config).
    pub fn update_whitelist(&mut self, roots: Vec<FsRoot>) {
        self.whitelist = roots;
    }
}
