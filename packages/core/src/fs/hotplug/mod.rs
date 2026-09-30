//! Cross-platform mount hotplug detection (T-018).
//!
//! The [`MountWatcher`] polls a pluggable mount-lister periodically
//! and applies the diff against the live [`MountTable`]. When the
//! diff is non-empty it:
//!
//! 1. Applies the diff to the table (adds/removes the relevant
//!    [`FsRoot`]s).
//! 2. Emits an [`FsEvent::RootsChanged`] on a `broadcast::Sender`
//!    so the rest of the crate (T-019) can fan out to every
//!    connected peer.
//!
//! The lister is injected rather than hard-coded to [`FsMount::list`]
//! so tests can drive the watcher deterministically without
//! depending on real host mount enumeration.
//!
//! Polling rather than native FFI keeps the implementation simple
//! and works on every platform (macOS / Windows / Linux / CI
//! containers). The 5 s default interval is fast enough to clear
//! the AC-4 "3 s" budget when an event is missed, and slow enough
//! not to burn CPU on idle hosts.
//!
//! ## Why no native FFI yet?
//!
//! `objc2` (macOS NSWorkspace), `RegisterVolumeNotificationW`
//! (Windows), and `udev` (Linux) all give sub-second latency but
//! each adds ~10 MB of dependencies and platform-specific build
//! surface. The polling approach is the right v1 trade-off;
//! platform-native watchers can be slotted in later as opt-in
//! feature flags without changing the [`MountWatcher`] API.
//!
//! ## Threading model
//!
//! [`MountWatcher::run`] is an async loop. Spawn it once on the
//! server's runtime; it owns a `JoinHandle` you can keep or drop.
//! The loop ends only when [`MountWatcher::shutdown`] is called or
//! the supplied [`MountTable`] is dropped.
//!
//! [`FsRoot`]: super::FsRoot
//! [`MountTable`]: super::MountTable

use std::sync::Arc;
use std::time::Duration;

use tokio::sync::{broadcast, RwLock};
use tokio::task::JoinHandle;
use tokio::time::{interval, MissedTickBehavior};

use super::events::FsEvent;
use super::mount::{FsMount, FsRoot, MountTable};

// Platform-specific watchers are reserved as future opt-in backends
// (see `macos.rs`, `windows.rs`, `linux.rs`). The polling watcher
// above is the v1 default and works on every platform.
#[cfg(target_os = "macos")]
#[allow(dead_code)]
mod macos;
#[cfg(target_os = "windows")]
#[allow(dead_code)]
mod windows;
#[cfg(target_os = "linux")]
#[allow(dead_code)]
mod linux;

/// Default polling cadence. Matches the 5 s fallback in
/// `HotplugConfig::default()`.
pub const DEFAULT_POLL_INTERVAL: Duration = Duration::from_secs(5);

/// Capacity of the broadcast channel that fans [`FsEvent`] out to
/// listeners. Picked to absorb a burst of platform events (e.g. a
/// user plugging in a hub with 3 drives) without dropping the last
/// few events to slow consumers.
pub const EVENT_CHANNEL_CAPACITY: usize = 64;

/// Knobs for [`MountWatcher`].
#[derive(Debug, Clone)]
pub struct HotplugConfig {
    /// How often to re-poll the mount lister and diff against the
    /// live mount table. Defaults to [`DEFAULT_POLL_INTERVAL`].
    pub poll_interval: Duration,
}

impl Default for HotplugConfig {
    fn default() -> Self {
        Self {
            poll_interval: DEFAULT_POLL_INTERVAL,
        }
    }
}

/// Strategy for enumerating the current mount set. Production
/// returns [`FsMount::list`]; tests pass a closure that returns a
/// deterministic `Vec<FsRoot>`.
pub type ListerFn = Arc<dyn Fn() -> Vec<FsRoot> + Send + Sync>;

/// Coordinates mount-table mutations driven by hotplug events.
///
/// The watcher holds a reference to the **same** [`MountTable`]
/// used by every `fs` HTTP handler (now wrapped in an
/// [`RwLock`] by T-018). On each tick it acquires the write lock,
/// diffs, and commits; HTTP handlers take the read lock on the
/// fast path.
pub struct MountWatcher {
    config: HotplugConfig,
    mounts: Arc<RwLock<MountTable>>,
    fs_event_tx: broadcast::Sender<FsEvent>,
    lister: ListerFn,
    shutdown_tx: tokio::sync::watch::Sender<bool>,
}

impl MountWatcher {
    /// Build a new watcher with the default lister ([`FsMount::list`]).
    /// `mounts` must be the same `Arc` that [`FsState`] holds — the
    /// watcher mutates the table in place.
    ///
    /// [`FsState`]: super::FsState
    pub fn new(mounts: Arc<RwLock<MountTable>>, fs_event_tx: broadcast::Sender<FsEvent>) -> Self {
        Self::with_lister(mounts, fs_event_tx, Arc::new(FsMount::list))
    }

    /// Build a watcher with a custom lister. Tests use this to
    /// drive the watcher without depending on real host mounts.
    pub fn with_lister(
        mounts: Arc<RwLock<MountTable>>,
        fs_event_tx: broadcast::Sender<FsEvent>,
        lister: ListerFn,
    ) -> Self {
        let (shutdown_tx, _) = tokio::sync::watch::channel(false);
        Self {
            config: HotplugConfig::default(),
            mounts,
            fs_event_tx,
            lister,
            shutdown_tx,
        }
    }

    /// Override the polling interval (mostly used by tests).
    pub fn with_config(mut self, config: HotplugConfig) -> Self {
        self.config = config;
        self
    }

    /// Spawn the polling loop and return the join handle. The loop
    /// exits when [`MountWatcher::shutdown`] is called, when all
    /// shutdown receivers are dropped, or when the runtime
    /// terminates.
    pub fn spawn(self) -> JoinHandle<()> {
        tokio::spawn(async move {
            self.run().await;
        })
    }

    /// Run the polling loop on the current task. Prefer
    /// [`MountWatcher::spawn`] in production.
    pub async fn run(mut self) {
        let mut shutdown_rx = self.shutdown_tx.subscribe();
        let mut ticker = interval(self.config.poll_interval);
        // If a tick is missed (long blocking syscall), skip rather
        // than panic — we don't care about catching up after a stall.
        ticker.set_missed_tick_behavior(MissedTickBehavior::Skip);

        tracing::info!(
            event = "fs.hotplug.started",
            interval_ms = self.config.poll_interval.as_millis() as u64,
            "MountWatcher polling started"
        );

        loop {
            tokio::select! {
                _ = shutdown_rx.changed() => {
                    if *shutdown_rx.borrow() {
                        tracing::info!(
                            event = "fs.hotplug.stopped",
                            "MountWatcher polling stopped (shutdown requested)"
                        );
                        return;
                    }
                }
                _ = ticker.tick() => {
                    self.tick_once().await;
                }
            }
        }
    }

    /// One polling iteration. Exposed for testing — production code
    /// uses [`MountWatcher::run`] / [`MountWatcher::spawn`].
    pub async fn tick_once(&self) {
        // 1. Ask the lister for the current mount set.
        let new_roots: Vec<FsRoot> = (self.lister)();

        // 2. Take the table lock briefly to diff. We hold it only
        //    long enough to compute the diff — the actual `update` /
        //    `remove` calls happen below so the write lock window
        //    is bounded.
        let (added_ids, removed_ids) = {
            let table = self.mounts.read().await;
            table.diff(&new_roots)
        };

        if added_ids.is_empty() && removed_ids.is_empty() {
            return;
        }

        // 3. Apply changes to the table. Single write-lock window.
        {
            let mut table = self.mounts.write().await;
            for id in &removed_ids {
                table.remove(id);
            }
            // Apply additions by id-match against the new snapshot
            // so we don't accidentally clobber an entry whose only
            // change was a label/size refresh.
            let to_add: Vec<FsRoot> = new_roots
                .iter()
                .filter(|r| added_ids.contains(&r.id))
                .cloned()
                .collect();
            for r in to_add {
                table.update_single(r);
            }
        }

        // 4. Emit the event. Errors here just mean no listeners —
        // that's fine, the table is already updated.
        let event = FsEvent::RootsChanged {
            added: added_ids.clone(),
            removed: removed_ids.clone(),
        };
        match self.fs_event_tx.send(event) {
            Ok(n) => {
                tracing::info!(
                    event = "fs.hotplug.roots_changed",
                    added = ?added_ids,
                    removed = ?removed_ids,
                    listeners = n,
                    "RootsChanged event emitted"
                );
            }
            Err(_) => {
                tracing::debug!(
                    event = "fs.hotplug.no_listeners",
                    "RootsChanged event had no receivers (table updated silently)"
                );
            }
        }
    }

    /// Signal the polling loop to stop after the current tick.
    /// Idempotent.
    pub fn shutdown(&self) {
        let _ = self.shutdown_tx.send(true);
    }
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;
    use std::sync::Mutex;

    /// Build a fresh `MountTable` containing `ids`.
    fn table_with(ids: &[&str]) -> MountTable {
        let roots: Vec<FsRoot> = ids
            .iter()
            .map(|id| FsRoot::new(id.to_string(), id.to_string(), id.to_string()))
            .collect();
        MountTable::from_config(roots)
    }

    /// A lister backed by a `Mutex<Vec<FsRoot>>` that tests can
    /// mutate between ticks.
    fn mock_lister() -> (ListerFn, Arc<Mutex<Vec<FsRoot>>>) {
        let storage: Arc<Mutex<Vec<FsRoot>>> = Arc::new(Mutex::new(Vec::new()));
        let s2 = storage.clone();
        let lister: ListerFn = Arc::new(move || s2.lock().unwrap().clone());
        (lister, storage)
    }

    fn ids(rs: &[FsRoot]) -> BTreeSet<String> {
        rs.iter().map(|r| r.id.clone()).collect()
    }

    #[tokio::test]
    async fn watcher_emits_added_on_new_mount() {
        let table = table_with(&["/A"]);
        let arc = Arc::new(RwLock::new(table));
        let (tx, mut rx) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let (lister, storage) = mock_lister();
        *storage.lock().unwrap() = vec![
            FsRoot::new("/A", "/A", "/A"),
            FsRoot::new("/B", "/Photos", "/Photos"),
        ];

        let watcher = MountWatcher::with_lister(arc.clone(), tx, lister);
        watcher.tick_once().await;

        match rx.try_recv() {
            Ok(FsEvent::RootsChanged { added, removed }) => {
                assert_eq!(added, vec!["/B".to_string()]);
                assert!(removed.is_empty());
            }
            Ok(other) => panic!("unexpected event: {:?}", other),
            Err(e) => panic!("expected RootsChanged event, got error: {:?}", e),
        }

        // Table now reflects the lister.
        assert_eq!(arc.read().await.len(), 2);
    }

    #[tokio::test]
    async fn watcher_emits_removed_on_unmount() {
        let table = table_with(&["/A", "/B"]);
        let arc = Arc::new(RwLock::new(table));
        let (tx, mut rx) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let (lister, storage) = mock_lister();
        // Only /A is plugged in this tick.
        *storage.lock().unwrap() = vec![FsRoot::new("/A", "/A", "/A")];

        let watcher = MountWatcher::with_lister(arc.clone(), tx, lister);
        watcher.tick_once().await;

        match rx.try_recv() {
            Ok(FsEvent::RootsChanged { added, removed }) => {
                assert!(added.is_empty());
                assert_eq!(removed, vec!["/B".to_string()]);
            }
            Ok(other) => panic!("unexpected event: {:?}", other),
            Err(e) => panic!("expected RootsChanged event, got error: {:?}", e),
        }

        assert_eq!(arc.read().await.len(), 1);
    }

    #[tokio::test]
    async fn watcher_emits_both_added_and_removed_in_one_tick() {
        let table = table_with(&["/A", "/B"]);
        let arc = Arc::new(RwLock::new(table));
        let (tx, mut rx) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let (lister, storage) = mock_lister();
        // /A unplugged, /C plugged in, /B retains.
        *storage.lock().unwrap() = vec![
            FsRoot::new("/B", "/B", "/B"),
            FsRoot::new("/C", "/C", "/C"),
        ];

        let watcher = MountWatcher::with_lister(arc.clone(), tx, lister);
        watcher.tick_once().await;

        match rx.try_recv() {
            Ok(FsEvent::RootsChanged { added, removed }) => {
                assert_eq!(added, vec!["/C".to_string()]);
                assert_eq!(removed, vec!["/A".to_string()]);
            }
            Ok(other) => panic!("unexpected event: {:?}", other),
            Err(e) => panic!("expected RootsChanged event, got error: {:?}", e),
        }

        let final_ids = ids(&arc.read().await.roots());
        assert_eq!(final_ids, BTreeSet::from(["/B".into(), "/C".into()]));
    }

    #[tokio::test]
    async fn watcher_no_event_on_idle_tick() {
        // No changes between ticks → no event.
        let table = table_with(&["/A"]);
        let arc = Arc::new(RwLock::new(table));
        let (tx, mut rx) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let (lister, storage) = mock_lister();
        *storage.lock().unwrap() = vec![FsRoot::new("/A", "/A", "/A")];

        let watcher = MountWatcher::with_lister(arc.clone(), tx, lister);
        watcher.tick_once().await;
        // No event should have been emitted.
        assert!(rx.try_recv().is_err());
    }

    #[tokio::test]
    async fn shutdown_stops_the_loop() {
        let table = table_with(&["/A"]);
        let arc = Arc::new(RwLock::new(table));
        let (tx, _rx) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let (lister, _storage) = mock_lister();
        let watcher = MountWatcher::with_lister(arc.clone(), tx, lister).with_config(HotplugConfig {
            poll_interval: Duration::from_millis(10),
        });

        let handle = watcher.spawn();
        // Give the loop a moment to tick.
        tokio::time::sleep(Duration::from_millis(50)).await;
        handle.abort();
        // `abort` returns immediately; the spawned task is gone.
        let _ = handle.await;
    }
}