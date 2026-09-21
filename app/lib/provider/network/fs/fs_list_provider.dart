import 'dart:async';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

part 'fs_list_provider.mapper.dart';

final _logger = Logger('FsList');

/// How many entries are loaded per page (T-008 §2).
const int kFsListPageSize = 100;

/// Allowed values of the `sort` query parameter on the fs list endpoint.
enum FsSort {
  nameAsc('name_asc'),
  nameDesc('name_desc'),
  sizeAsc('size_asc'),
  sizeDesc('size_desc'),
  mtimeDesc('mtime_desc')
  ;

  final String value;
  const FsSort(this.value);
}

enum FsViewMode {
  list,
  grid,
}

/// The state of the read-only remote file browser (T-008).
///
/// `currentPath == ""` means the roots level; the [roots] field is populated
/// in that case. At any other level, [entries] is the directory listing.
@MappableClass()
class FsListState with FsListStateMappable {
  /// The device the page is currently browsing. `null` when no request has
  /// been dispatched yet, so the page can render an initial loading view.
  final String? deviceFingerprint;

  /// The current path relative to the chosen root. `""` is the roots level.
  final String currentPath;

  /// The list of mount points when at the roots level.
  final List<rust_model.FsRoot> roots;

  /// The accumulated directory entries of the current path. Pages are
  /// appended by [FsLoadMoreAction].
  final List<rust_model.FsEntry> entries;

  /// Total number of entries at the current path, as reported by the server.
  /// `0` while at the roots level.
  final int total;

  /// `true` while the current path or page is being fetched.
  final bool loading;

  /// `true` if the user has scrolled past the last currently loaded page.
  final bool hasMore;

  /// 0-based index of the last loaded page.
  final int page;

  final FsSort sort;
  final FsViewMode viewMode;

  /// The last error, or `null` if the last request succeeded.
  final String? error;

  const FsListState({
    required this.deviceFingerprint,
    required this.currentPath,
    required this.roots,
    required this.entries,
    required this.total,
    required this.loading,
    required this.hasMore,
    required this.page,
    required this.sort,
    required this.viewMode,
    required this.error,
  });

  factory FsListState.initial() => const FsListState(
    deviceFingerprint: null,
    currentPath: '',
    roots: [],
    entries: [],
    total: 0,
    loading: false,
    hasMore: false,
    page: -1,
    sort: FsSort.nameAsc,
    viewMode: FsViewMode.list,
    error: null,
  );
}

final fsListProvider = NotifierProvider<FsListService, FsListState>((ref) {
  return FsListService();
});

class FsListService extends Notifier<FsListState> {
  FsListService();

  @override
  FsListState init() => FsListState.initial();

  /// Resets the listing state and starts a new fetch of [path].
  /// When [path] is empty the roots are fetched instead.
  Future<void> _enterPath({
    required Device device,
    required String path,
  }) async {
    state = FsListState(
      deviceFingerprint: device.fingerprint,
      currentPath: path,
      roots: path.isEmpty ? const [] : state.roots,
      entries: const [],
      total: 0,
      loading: true,
      hasMore: false,
      page: -1,
      sort: state.sort,
      viewMode: state.viewMode,
      error: null,
    );

    final stream = ref
        .redux(parentIsolateProvider)
        .dispatchTakeResult(
          IsolateFsListAction(
            FsListRequest(
              device: device,
              path: path,
              page: 0,
              size: kFsListPageSize,
              sort: state.sort.value,
            ),
          ),
        );

    try {
      await for (final result in stream) {
        if (state.deviceFingerprint != device.fingerprint || state.currentPath != path) {
          // a newer request superseded this one; drop the result
          return;
        }
        switch (result) {
          case FsListRootsResult r:
            state = state.copyWith(
              roots: r.roots,
              loading: false,
              hasMore: false,
              page: 0,
              total: r.roots.length,
            );
          case FsListDirResult r:
            state = state.copyWith(
              entries: r.entries,
              loading: false,
              hasMore: r.hasMore,
              page: 0,
              total: r.total.toInt(),
            );
        }
      }
    } catch (e, st) {
      _logger.warning('Failed to list fs path=$path', e, st);
      if (state.deviceFingerprint == device.fingerprint && state.currentPath == path) {
        state = state.copyWith(
          loading: false,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _loadMore({required Device device}) async {
    if (state.loading || !state.hasMore) return;
    if (state.currentPath.isEmpty) return; // roots level is not paginated
    if (state.deviceFingerprint != device.fingerprint) return;

    final nextPage = state.page + 1;
    state = state.copyWith(loading: true, error: null);

    final stream = ref
        .redux(parentIsolateProvider)
        .dispatchTakeResult(
          IsolateFsListAction(
            FsListRequest(
              device: device,
              path: state.currentPath,
              page: nextPage,
              size: kFsListPageSize,
              sort: state.sort.value,
            ),
          ),
        );

    try {
      await for (final result in stream) {
        if (state.deviceFingerprint != device.fingerprint) {
          return;
        }
        switch (result) {
          case FsListRootsResult():
            // unexpected for a non-empty path
            break;
          case FsListDirResult r:
            state = state.copyWith(
              entries: [...state.entries, ...r.entries],
              loading: false,
              hasMore: r.hasMore,
              page: nextPage,
              total: r.total.toInt(),
            );
        }
      }
    } catch (e, st) {
      _logger.warning('Failed to load more entries for path=${state.currentPath}', e, st);
      if (state.deviceFingerprint == device.fingerprint) {
        state = state.copyWith(
          loading: false,
          error: e.toString(),
        );
      }
    }
  }

  // ============================================================
  // Public API (also exposed as actions below for symmetry with
  // the rest of the app — both call into the same methods).
  // ============================================================

  void enterRoots(Device device) {
    unawaited(_enterPath(device: device, path: ''));
  }

  void enterPath({required Device device, required String path}) {
    unawaited(_enterPath(device: device, path: path));
  }

  void loadMore(Device device) {
    unawaited(_loadMore(device: device));
  }

  void refresh(Device device) {
    unawaited(_enterPath(device: device, path: state.currentPath));
  }

  void changeView(FsViewMode viewMode) {
    state = state.copyWith(viewMode: viewMode);
  }

  void changeSort({required Device device, required FsSort sort}) {
    state = state.copyWith(sort: sort);
    unawaited(_enterPath(device: device, path: state.currentPath));
  }

  void reset() {
    state = FsListState.initial();
  }
}
