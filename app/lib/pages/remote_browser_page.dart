import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/remote_browser/widgets/breadcrumb.dart';
import 'package:localsend_app/pages/remote_browser/widgets/empty_state.dart';
import 'package:localsend_app/pages/remote_browser/widgets/grid_view.dart';
import 'package:localsend_app/pages/remote_browser/widgets/list_view.dart';
import 'package:localsend_app/pages/remote_browser/widgets/sort_menu.dart';
import 'package:localsend_app/pages/remote_browser/widgets/view_mode_toggle.dart';
import 'package:localsend_app/provider/network/fs/fs_list_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;
import 'package:refena_flutter/refena_flutter.dart';

/// T-008: remote filesystem browser page.
///
/// `fingerprint` is the target device's fingerprint, looked up in
/// [NearbyDevicesState.allDevices]. If the device has gone offline
/// (e.g. the page was left open across a network drop) the page falls
/// back to a "device not available" view rather than crash.
///
/// State flow (mirrors the [FsListService] state machine):
///   * `loading && entries.isEmpty && roots.isEmpty` → skeleton
///   * `error != null`                             → error card
///   * `currentPath.isEmpty && roots.isEmpty`      → roots empty
///   * `currentPath.isNotEmpty && entries.isEmpty && !loading` → empty folder
///   * otherwise                                   → list or grid body
///
/// Tapping a folder entry navigates into it; tapping a root opens it.
/// Tapping a file entry fires the file action sheet — that bridge lives
/// in T-009.
class RemoteBrowserPage extends StatefulWidget {
  final String fingerprint;
  const RemoteBrowserPage({required this.fingerprint, super.key});

  @override
  State<RemoteBrowserPage> createState() => _RemoteBrowserPageState();
}

class _RemoteBrowserPageState extends State<RemoteBrowserPage> with Refena {
  String? _lastDeviceFingerprint;
  bool _initialFetchKicked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeKickInitialFetch();
    });
  }

  Device? _deviceOrNull() {
    if (!mounted) return null;
    return ref.read(nearbyDevicesProvider.select((s) => s.allDevices[widget.fingerprint]));
  }

  void _maybeKickInitialFetch() {
    if (_initialFetchKicked) return;
    final device = _deviceOrNull();
    if (device == null) return;
    final state = ref.read(fsListProvider);
    // Only fetch when the state is fresh for this device — otherwise
    // the isolate already has the latest data for the same path.
    if (state.deviceFingerprint == device.fingerprint && state.currentPath.isNotEmpty) {
      return;
    }
    ref.notifier(fsListProvider).enterRoots(device);
    _initialFetchKicked = true;
    _lastDeviceFingerprint = device.fingerprint;
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(
      nearbyDevicesProvider.select((s) => s.allDevices[widget.fingerprint]),
    );
    final fsState = ref.watch(fsListProvider);

    // Detect a device swap (different fingerprint) and re-fetch.
    if (device != null && _lastDeviceFingerprint != device.fingerprint) {
      _lastDeviceFingerprint = device.fingerprint;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.notifier(fsListProvider).enterRoots(device);
      });
    }

    if (device == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.remoteBrowser.title)),
        body: const Center(child: Text('—')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${t.remoteBrowser.title} · ${device.alias}'),
        actions: [
          FsSortMenu(
            current: fsState.sort,
            onChanged: (s) => ref.notifier(fsListProvider).changeSort(device: device, sort: s),
          ),
          FsViewModeToggle(
            current: fsState.viewMode,
            onChanged: (m) => ref.notifier(fsListProvider).changeView(m),
          ),
        ],
      ),
      body: Column(
        children: [
          FsBreadcrumb(
            path: fsState.currentPath,
            onNavigate: (path) {
              if (path.isEmpty) {
                ref.notifier(fsListProvider).enterRoots(device);
              } else {
                ref.notifier(fsListProvider).enterPath(device: device, path: path);
              }
            },
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(device, fsState)),
        ],
      ),
    );
  }

  Widget _buildBody(Device device, FsListState state) {
    if (state.error != null && state.entries.isEmpty && state.roots.isEmpty) {
      return FsErrorState(
        message: state.error,
        onRetry: () {
          if (state.currentPath.isEmpty) {
            ref.notifier(fsListProvider).enterRoots(device);
          } else {
            ref.notifier(fsListProvider).refresh(device);
          }
        },
      );
    }

    if (state.loading && state.entries.isEmpty && state.roots.isEmpty) {
      return const FsLoadingSkeleton();
    }

    if (state.currentPath.isEmpty) {
      if (state.roots.isEmpty) {
        return FsEmptyState(
          isRoots: true,
          onRetry: () => ref.notifier(fsListProvider).enterRoots(device),
        );
      }
      if (state.viewMode == FsViewMode.grid) {
        return FsRootsGridBody(
          roots: state.roots,
          onTapRoot: (root) => ref
              .notifier(fsListProvider)
              .enterPath(
                device: device,
                path: root.id,
              ),
        );
      }
      return FsRootsBody(
        roots: state.roots,
        onTapRoot: (root) => ref
            .notifier(fsListProvider)
            .enterPath(
              device: device,
              path: root.id,
            ),
      );
    }

    if (state.entries.isEmpty && !state.loading) {
      return FsEmptyState(
        isRoots: false,
        onRetry: () => ref.notifier(fsListProvider).refresh(device),
      );
    }

    if (state.viewMode == FsViewMode.grid) {
      return FsGridBody(
        entries: state.entries,
        onTapEntry: (entry) => _onTapEntry(device, entry),
      );
    }

    return FsListBody(
      entries: state.entries,
      hasMore: state.hasMore,
      loading: state.loading,
      onTapEntry: (entry) => _onTapEntry(device, entry),
      onLoadMore: () => ref.notifier(fsListProvider).loadMore(device),
    );
  }

  void _onTapEntry(Device device, rust.FsEntry entry) {
    if (entry.isDir) {
      final base = ref.read(fsListProvider).currentPath;
      final next = base.isEmpty ? entry.name : '$base/${entry.name}';
      ref.notifier(fsListProvider).enterPath(device: device, path: next);
    } else {
      // T-009 entry point: file action sheet is wired in T-009. For P1
      // the page is read-only; we surface a no-op toast so the user
      // gets feedback rather than a silent dead tap.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(entry.name),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
}
