//! Linux-specific hotplug backend (T-018 future work).
//!
//! The v1 watcher uses polling via [`super::MountWatcher`] with
//! `FsMount::list()` as its lister; that covers every platform
//! (including Linux) without adding the `udev` crate. This module
//! is the planned hook point for a `udev::Monitor` listener that
//! would give sub-second latency on Linux hosts.
//!
//! Left intentionally empty for now — `super::MountWatcher` is
//! the production implementation on every platform.

#![cfg_attr(not(target_os = "linux"), allow(dead_code))]