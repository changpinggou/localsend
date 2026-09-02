//! `FsEvent` — the channel emitted to the Dart side.
//!
//! Some `fs` operations need to push information to the Flutter UI
//! rather than wait for a request/response cycle:
//!
//! - `RootsChanged` — a mount point appeared or disappeared (USB stick
//!   plugged in, network share unmounted). T-019 will trigger this from
//!   platform-specific hotplug events.
//! - `AuditLog`     — a write happened on behalf of a remote peer.
//!   T-015 will emit this on every mutating operation.
//! - `QuotaWarn`    — reserved for future quota support. Carrying the
//!   variant now means we don't have to bump the FRB schema later.
//!
//! The enum is plain data; serialisation is derived so it crosses the
//! FRB boundary without any custom glue. T-019 will add the runtime
//! sender / channel wiring.

use serde::{Deserialize, Serialize};

/// Events emitted by the `fs` module to the Dart layer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum FsEvent {
    /// A mount point was added or removed. `added` carries the new
    /// mount's alias; `removed` carries the alias that just went away.
    /// Either list may be empty.
    RootsChanged {
        /// Aliases of newly available mount points.
        added: Vec<String>,
        /// Aliases of mount points that are no longer available.
        removed: Vec<String>,
    },

    /// A write operation just completed on behalf of a remote peer.
    /// `peer` is the SHA-256 fingerprint of the client certificate.
    /// T-025 will turn these into the user-visible audit log.
    AuditLog {
        /// Fingerprint of the peer that initiated the action.
        peer: String,
        /// `mkdir`, `upload`, `move`, `delete`, etc.
        op: String,
        /// Logical path the action targeted, e.g. `Photos/2026/IMG.jpg`.
        path: String,
        /// Unix epoch in seconds.
        ts: i64,
    },

    /// Reserved for future quota support. Currently never emitted.
    QuotaWarn {
        /// Alias of the mount point that crossed the threshold.
        mount: String,
        /// Percentage of the quota that is now in use, `0..=100`.
        used_pct: u8,
    },
}
