// ignore_for_file: prefer_const_constructors
import 'package:flutter/foundation.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:refena_flutter/refena_flutter.dart';

/// State for T-020: a per-device cache of the whitelist pushed
/// by the server's `MountWatcher` via `FsRootsChanged` events.
///
/// One cache entry per remote device (keyed by fingerprint) so
/// switching back to a previously-visited device doesn't trigger
/// a re-fetch of the whitelist. The server only sends a new
/// snapshot when the whitelist actually changes, so we don't
/// need a per-entry version counter — `rootsByDevice` is the
/// source of truth.
///
/// Implementation note: refena 3.5 doesn't ship a
/// `NotifierProviderFamily`. We achieve the same effect by
/// keeping a `Map<String, _DeviceRoots>` inside a single
/// `NotifierProvider`; consumers index by fingerprint.
@immutable
class FsRootsState {
  /// Per-device cache: fingerprint → last reported whitelist +
  /// when we got it.
  final Map<String, FsDeviceRoots> rootsByDevice;

  const FsRootsState({required this.rootsByDevice});

  factory FsRootsState.initial() => const FsRootsState(rootsByDevice: {});

  /// Convenience: look up the cache entry for `fingerprint`,
  /// returning an empty list if we've never seen it.
  List<rust_model.FsRoot> rootsFor(String fingerprint) {
    return rootsByDevice[fingerprint]?.roots ?? const [];
  }

  /// Convenience: `true` if `path` is still under some
  /// whitelisted root for `fingerprint`.
  bool containsRootFor(String fingerprint, String path) {
    final entry = rootsByDevice[fingerprint];
    if (entry == null) return false;
    for (final r in entry.roots) {
      if (path == r.id) return true;
      if (path.startsWith('${r.id}/')) return true;
    }
    return false;
  }
}

@immutable
class FsDeviceRoots {
  final List<rust_model.FsRoot> roots;
  final DateTime updatedAt;
  const FsDeviceRoots({required this.roots, required this.updatedAt});
}

/// T-020: app-wide cache of per-device whitelists. Single global
/// `NotifierProvider`; clients index by fingerprint.
final fsRootsProvider = NotifierProvider<FsRootsService, FsRootsState>(
  (ref) => FsRootsService(),
);

class FsRootsService extends Notifier<FsRootsState> {
  @override
  FsRootsState init() => FsRootsState.initial();

  /// Replace the cached whitelist for one device with the
  /// snapshot the server just pushed. Called from
  /// `server_provider.dart` whenever a
  /// `HttpServerFsRootsChangedEvent` arrives.
  void update(String fingerprint, List<rust_model.FsRoot> roots) {
    final next = Map<String, FsDeviceRoots>.from(state.rootsByDevice);
    next[fingerprint] = FsDeviceRoots(roots: roots, updatedAt: DateTime.now());
    state = FsRootsState(rootsByDevice: next);
  }
}
