//! Server-side file system access (LocalU feature).
//!
//! The `fs` module is the implementation of the "挂载端" (mounted-end) side of
//! LocalU: it exposes a sandboxed view of the host filesystem to remote peers
//! over the existing v2 HTTP server, with the goal of letting a phone
//! browse, read, write, move and delete files on a desktop peer behind a
//! strict whitelist + path-traversal guard.
//!
//! ## Layout
//!
//! - [`config`]    – `FsConfig`: server-side tuning (whitelist, recycle bin,
//!   max upload size, thumbnail sizing, list pagination). Pure data, `Default`
//!   derived.
//! - [`mount`]     – `FsRoot`, `MountTable` and `FsMount`: which host
//!   directories are exposed and how they are discovered. Filled in by
//!   T-002.
//! - [`path`]      – `FsError`, `FsPath` and `PathGuard`: the path-traversal
//!   sandbox that backs every read/write endpoint. T-004 ships the
//!   hardened pass (OWASP, percent-decoding, symlink-loop detection,
//!   TOCTOU re-check).
//! - [`rest`]      – `FsState`, `FS_PREFIX` and the three read-only
//!   handlers (`/roots`, `/list`, `/download`). T-003.
//! - [`events`]    – `FsEvent`: the channel emitted to the Dart side on
//!   `roots-changed` etc. Filled in by T-019.
//!
//! All public items are `pub use`'d here so the rest of the crate can just
//! write `crate::fs::FsConfig` rather than `crate::fs::config::FsConfig`.
//!
//! ## Feature gate
//!
//! The whole module is feature-gated behind `fs`; disabling the feature
//! makes the symbol disappear entirely (the `#[cfg(feature = "fs")]`
//! declarations in `lib.rs` are the only place that has to know).

mod config;
mod events;
mod mount;
mod path;
mod rest;

pub use config::FsConfig;
pub use events::FsEvent;
pub use mount::{FsMount, FsRoot, MountTable};
pub use path::{FsError, FsPath, PathDeniedReason, PathGuard};
pub use rest::{handle_request, register, FsEntry, FsState, ListResponse, RootsResponse, FS_PREFIX};

#[cfg(test)]
mod tests {
    //! Cross-module integration tests for the `fs` scaffolding.
    //!
    //! Per-module tests live in `mount.rs`, `config.rs`, etc. The
    //! tests in this file are the ones that need more than one
    //! submodule to be meaningful: defaults, the fail-closed
    //! `PathGuard` stub, the `FsEvent` variants and the
    //! `FsState` build path.
    //!
    //! T-002 added [`FsMount`] and the full `FsRoot` field set;
    //! their dedicated tests now live in `mount.rs`.

    use super::{FsConfig, FsError, FsEvent, FsRoot, FsState, MountTable, PathDeniedReason, PathGuard};

    #[test]
    fn fs_config_defaults_match_requirements() {
        let cfg = FsConfig::default();
        // N-SEC-2: server is locked down out of the box. The
        // whitelist type is `Vec<FsRoot>` now, so the assertion is
        // a `Vec` emptiness check rather than a path check.
        assert!(cfg.whitelist.is_empty(), "default whitelist must be empty");
        // N-LIM-2: 10 GiB upload ceiling.
        assert_eq!(cfg.max_upload_size, 10 * 1024 * 1024 * 1024);
        // N-LIM-3: 200 px thumbnails.
        assert_eq!(cfg.thumbnail_max_dim, 200);
        // N-LIM-4: 200 entries per list page.
        assert_eq!(cfg.max_list_page_size, 200);
        // Recycle bin defaults to off so Linux / *BSD users aren't surprised
        // by "file gone" complaints; T-015 may revisit this per platform.
        assert!(!cfg.recycle_bin);
    }

    #[test]
    fn fs_config_update_whitelist_replaces() {
        // T-002 hook: the IPC handler and the roots-changed event
        // both call `update_whitelist`. Cover the basic round-trip
        // here so a regression in the trivial path is caught
        // before it gets wired into the network layer.
        let mut cfg = FsConfig::default();
        assert!(cfg.whitelist.is_empty());

        cfg.update_whitelist(vec![FsRoot::new("/data/Photos", "Photos", "/data/Photos")]);
        assert_eq!(cfg.whitelist.len(), 1);
        assert_eq!(cfg.whitelist[0].label, "Photos");

        cfg.update_whitelist(Vec::new());
        assert!(cfg.whitelist.is_empty(), "update_whitelist must clear the list");
    }

    #[test]
    fn mount_table_starts_empty() {
        let t = MountTable::new();
        assert!(t.is_empty());
        assert_eq!(t.len(), 0);
        assert!(t.roots().is_empty());
    }

    #[test]
    fn path_guard_rejects_unknown_root_with_dedicated_variant() {
        // After T-003, `PathGuard::check` is no longer a stub —
        // it works for paths under a whitelisted root. What stays
        // fail-closed is the *empty whitelist*: every input is
        // rejected with `PathDenied { OutsideWhitelist, .. }`,
        // never with `NotFound` or another reason (so a UI can
        // show "this share is not exposed" rather than "you
        // tried to escape").
        let guard = PathGuard::new(&MountTable::new());
        let err = guard.check("Photos/IMG_0001.jpg").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::OutsideWhitelist, .. }));
    }

    #[test]
    fn fs_event_variants_are_distinguishable() {
        // Compile-time check that the three variants exist. If someone
        // deletes a variant the build will fail here rather than at the
        // call site, because we pattern-match on every variant.
        let roots = FsEvent::RootsChanged { added: vec!["USB".into()], removed: vec![] };
        let audit = FsEvent::AuditLog { peer: "AB".into(), op: "mkdir".into(), path: "Photos".into(), ts: 1 };
        let quota = FsEvent::QuotaWarn { mount: "Photos".into(), used_pct: 80 };

        match roots {
            FsEvent::RootsChanged { .. } => {}
            _ => panic!("RootsChanged discriminant drifted"),
        }
        match audit {
            FsEvent::AuditLog { .. } => {}
            _ => panic!("AuditLog discriminant drifted"),
        }
        match quota {
            FsEvent::QuotaWarn { .. } => {}
            _ => panic!("QuotaWarn discriminant drifted"),
        }
    }

    #[test]
    fn fs_state_can_be_built_from_config_and_mounts() {
        // T-003 wiring smoke test: an FsState can be constructed
        // from a config + a mount table. The integration with the
        // v2 server (AppState.fs, dispatch arms) is exercised
        // there.
        let state = FsState::new(FsConfig::default(), MountTable::new());
        assert!(state.config.whitelist.is_empty());
        assert!(state.mounts.is_empty());
        // The PathGuard is wired automatically by `FsState::new`.
        assert!(state.guard.table().is_empty());
    }
}
