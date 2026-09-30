//! macOS-specific hotplug backend (T-018 future work).
//!
//! The v1 watcher uses polling via [`super::MountWatcher`] with
//! `FsMount::list()` as its lister; that covers every platform
//! (including macOS) without adding FFI dependencies. This module
//! is the planned hook point for `NSWorkspace.didMountNotification`
//! / `didUnmountNotification` via `objc2`, which would give
//! sub-second latency on macOS hosts.
//!
//! Left intentionally empty for now — `super::MountWatcher` is
//! the production implementation on every platform.

#![cfg_attr(not(target_os = "macos"), allow(dead_code))]