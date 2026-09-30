//! Windows-specific hotplug backend (T-018 future work).
//!
//! The v1 watcher uses polling via [`super::MountWatcher`] with
//! `FsMount::list()` as its lister; that covers every platform
//! (including Windows) without adding FFI dependencies. This
//! module is the planned hook point for `RegisterVolumeNotificationW`
//! (`DBT_DEVICEARRIVAL` / `DBT_DEVICEREMOVECOMPLETE`), reusing the
//! `windows-sys = 0.59` dependency that's already in
//! `Cargo.toml`.
//!
//! Left intentionally empty for now — `super::MountWatcher` is
//! the production implementation on every platform.

#![cfg_attr(not(target_os = "windows"), allow(dead_code))]