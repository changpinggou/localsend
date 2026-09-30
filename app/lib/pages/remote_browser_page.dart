import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/media_preview/image_preview_page.dart';
import 'package:localsend_app/pages/remote_browser/widgets/breadcrumb.dart';
import 'package:localsend_app/pages/remote_browser/widgets/context_menu.dart';
import 'package:localsend_app/pages/remote_browser/widgets/delete_confirm_dialog.dart';
import 'package:localsend_app/pages/remote_browser/widgets/empty_state.dart';
import 'package:localsend_app/pages/remote_browser/widgets/file_action_sheet.dart';
import 'package:localsend_app/pages/remote_browser/widgets/grid_view.dart';
import 'package:localsend_app/pages/remote_browser/widgets/list_view.dart';
import 'package:localsend_app/pages/remote_browser/widgets/mkdir_dialog.dart';
import 'package:localsend_app/pages/remote_browser/widgets/move_target_picker.dart';
import 'package:localsend_app/pages/remote_browser/widgets/multi_select_bar.dart';
import 'package:localsend_app/pages/remote_browser/widgets/rename_dialog.dart';
import 'package:localsend_app/pages/remote_browser/widgets/selection_list_view.dart';
import 'package:localsend_app/pages/remote_browser/widgets/sort_menu.dart';
import 'package:localsend_app/pages/remote_browser/widgets/upload_action_sheet.dart';
import 'package:localsend_app/pages/remote_browser/widgets/upload_queue_bar.dart';
import 'package:localsend_app/pages/remote_browser/widgets/view_mode_toggle.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/fs/fs_download_provider.dart';
import 'package:localsend_app/provider/network/fs/fs_list_provider.dart';
import 'package:localsend_app/provider/network/fs/fs_mutation_provider.dart';
import 'package:localsend_app/provider/network/fs/fs_roots_provider.dart';
import 'package:localsend_app/provider/network/fs/fs_upload_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/security_provider.dart';
import 'package:localsend_app/util/native/pick_for_upload.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust_http;
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
  int? _lastRootsCount;
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
    // T-008 follow-up: filter our own self-fingerprint out so we
    // don't pin our own cert against the remote server when the
    // page was pushed before 14c5437f's filter was applied (or for
    // a stale widget.fingerprint that the send_tab filter would
    // have removed by now). The device's IP is otherwise fine, so
    // we read all devices and pick by fingerprint but exclude self.
    final selfFingerprint = ref.watch(deviceFullInfoProvider).fingerprint;
    final device = ref.watch(
      nearbyDevicesProvider.select((s) {
        final all = s.allDevices;
        if (all.containsKey(widget.fingerprint) && widget.fingerprint != selfFingerprint) {
          return all[widget.fingerprint];
        }
        // widget.fingerprint was the self-fingerprint (filter would
        // have caught it) — fall back to the first peer so the page
        // can still render something useful. In practice the page is
        // re-pushed by the user tapping a non-self PeerRow, so the
        // fallback rarely fires.
        return all.values.firstWhere((d) => d.fingerprint != selfFingerprint, orElse: () => all[widget.fingerprint]!);
      }),
    );
    final fsState = ref.watch(fsListProvider);
    final mutationState = ref.watch(fsMutationProvider);
    // T-020: also watch the per-device whitelist cache. The
    // build is already triggered by `fsState`; the rebuild is
    // cheap, and this gives us the diff we need to decide
    // which toast to show.
    final rootsState = ref.watch(fsRootsProvider);

    // Detect a device swap (different fingerprint) and re-fetch.
    if (device != null && _lastDeviceFingerprint != device.fingerprint) {
      _lastDeviceFingerprint = device.fingerprint;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.notifier(fsListProvider).enterRoots(device);
      });
    }

    // T-020: surface a snackbar whenever the per-device
    // whitelist changed. Compare counts against the value
    // captured in the previous frame (`_lastRootsCount`).
    final nextEntry = rootsState.rootsByDevice[device?.fingerprint];
    final nextCount = nextEntry?.roots.length;
    if (_lastRootsCount != null && nextCount != null && nextCount != _lastRootsCount) {
      // Schedule on the next frame so we don't show a snackbar
      // during the build pass (which would race with the
      // Scaffold's overlay tree).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (nextCount > _lastRootsCount!) {
          context.showSnackBar(t.fsBrowser.rootsChangedAdded);
        } else {
          // If the user's path was invalidated by the removal,
          // server_provider already called `forceToRoot()`; the
          // snackbar confirms it.
          if (fsState.currentPath.isEmpty) {
            context.showSnackBar(t.fsBrowser.rootsInvalidatedForcedToRoot);
          } else {
            context.showSnackBar(t.fsBrowser.rootsChangedRemoved);
          }
        }
      });
    }
    _lastRootsCount = nextCount;

    if (device == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.remoteBrowser.title)),
        body: const Center(child: Text('—')),
      );
    }

    // T-016: 多选模式时显示不同的 AppBar
    final isMultiSelect = mutationState.isMultiSelectMode;

    return Scaffold(
      appBar: AppBar(
        title: isMultiSelect ? Text('已选择 ${mutationState.selectedPaths.length} 项') : Text('${t.remoteBrowser.title} · ${device.alias}'),
        leading: isMultiSelect
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => ref.notifier(fsMutationProvider).exitMultiSelect(),
              )
            : null,
        actions: isMultiSelect
            ? [
                // 全选按钮
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: () => _selectAll(device, fsState),
                ),
              ]
            : [
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
          if (!isMultiSelect)
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
          Expanded(child: _buildBody(device, fsState, mutationState)),
          if (isMultiSelect)
            FsMultiSelectBar(
              selectedCount: mutationState.selectedPaths.length,
              onMove: () => _showMoveDialog(device, mutationState),
              onDelete: () => _showDeleteDialog(device, mutationState),
              onCancel: () => ref.notifier(fsMutationProvider).exitMultiSelect(),
            )
          else
            const FsUploadQueueBar(),
        ],
      ),
      floatingActionButton: !isMultiSelect && fsState.currentPath.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _showUploadMenu(device),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  /// T-016: 全选当前目录的所有项
  void _selectAll(Device device, FsListState fsState) {
    for (final entry in fsState.entries) {
      final fullPath = fsState.currentPath.isEmpty ? entry.name : '${fsState.currentPath}/${entry.name}';
      ref.notifier(fsMutationProvider).toggleSelection(fullPath);
    }
  }

  Widget _buildBody(Device device, FsListState state, FsMutationData mutationState) {
    if (state.error != null && state.entries.isEmpty && state.roots.isEmpty) {
      return FsErrorState(
        message: state.error,
        reason: state.errorReason,
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

    // T-016: 多选模式使用可选择列表
    if (mutationState.isMultiSelectMode) {
      return FsSelectableListBody(
        entries: state.entries,
        selectedPaths: mutationState.selectedPaths,
        currentPath: state.currentPath,
        hasMore: state.hasMore,
        loading: state.loading,
        onTapEntry: (entry) => _onTapEntryInMultiSelect(device, state, entry),
        onLongPressEntry: (entry) {
          debugPrint('[T-016 DEBUG] FsSelectableListBody onLongPressEntry triggered for: ${entry.name}');
          _onLongPressEntry(device, state, entry);
        },
        onLoadMore: () => ref.notifier(fsListProvider).loadMore(device),
      );
    }

    if (state.viewMode == FsViewMode.grid) {
      return FsGridBody(
        entries: state.entries,
        onTapEntry: (entry) => _onTapEntry(device, entry),
        onLongPressEntry: (entry) {
          debugPrint('[T-016 DEBUG] FsGridBody onLongPressEntry triggered for: ${entry.name}');
          _onLongPressEntry(device, state, entry);
        },
        device: device,
        currentPath: state.currentPath,
      );
    }

    debugPrint('[T-016 DEBUG] Building FsListBody with onLongPressEntry for ${state.entries.length} entries');
    return FsListBody(
      entries: state.entries,
      hasMore: state.hasMore,
      loading: state.loading,
      onTapEntry: (entry) => _onTapEntry(device, entry),
      onLongPressEntry: (entry) {
        debugPrint('[T-016 DEBUG] FsListBody onLongPressEntry triggered for: ${entry.name}');
        _onLongPressEntry(device, state, entry);
      },
      onLoadMore: () => ref.notifier(fsListProvider).loadMore(device),
      device: device,
      currentPath: state.currentPath,
    );
  }
  // ignore: discarded_futures

  /// Dispatches the entry tap. Folder taps are synchronous; file
  /// taps run an async download-and-save flow whose outcome is
  /// reported via a snackbar inside [_handleFileTap].
  // The async path is fire-and-forget — errors surface as a snackbar.
  // ignore: discarded_futures
  void _onTapEntry(Device device, rust.FsEntry entry) {
    if (entry.isDir) {
      final base = ref.read(fsListProvider).currentPath;
      final next = base.isEmpty ? entry.name : '$base/${entry.name}';
      ref.notifier(fsListProvider).enterPath(device: device, path: next);
    } else {
      // Async file action sheet + download + save flow. Outcome is
      // surfaced via a snackbar from inside `_handleFileTap`.
      _handleFileTap(device, entry);
    }
  }

  /// T-009: show the file action sheet, run the picked action, and
  /// surface the outcome as a snackbar. `progress` events come from
  /// the provider via the existing [ref.watch] above, so the page
  /// already rebuilds as bytes stream in.
  Future<void> _handleFileTap(Device device, rust.FsEntry entry) async {
    final action = await showFileActionSheet(context, entry: entry);
    if (action == null || !mounted) return;

    final base = ref.read(fsListProvider).currentPath;
    final fullPath = base.isEmpty ? entry.name : '$base/${entry.name}';

    // Show a "Downloading…" snackbar with a progress tick via a
    // setState. The page already watches fsDownloadProvider, so the
    // snackbar message can stay simple here.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.fsDownload.downloading),
        duration: const Duration(seconds: 30),
      ),
    );

    final downloadService = ref.notifier(fsDownloadProvider);
    final result = await performFileAction(
      downloadService: downloadService,
      device: device,
      entry: entry,
      fullPath: fullPath,
      action: action,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    final msg = switch (result.action) {
      FsFileAction.saveToGallery => result.failed ? t.fsDownload.galleryDenied : t.fsDownload.savedToGallery,
      FsFileAction.saveToFiles => result.failed ? t.fsDownload.failedTitle : t.fsDownload.savedToFiles(path: result.savedPath ?? ''),
      FsFileAction.preview => t.fsDownload.complete,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );

    if (result.action == FsFileAction.preview && result.savedPath != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImagePreviewPage(
            localPath: result.savedPath!,
            title: entry.name,
          ),
        ),
      );
    }
  }

  /// T-012: show upload action sheet and handle the selected action.
  Future<void> _showUploadMenu(Device device) async {
    final action = await showUploadActionSheet(context);
    if (action == null || !mounted) return;

    final currentPath = ref.read(fsListProvider).currentPath;
    if (currentPath.isEmpty) {
      // Cannot upload to root view
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.remoteBrowser.emptyFolder)),
      );
      return;
    }

    switch (action) {
      case FsUploadAction.fromPhotos:
        await _handlePickMedia(device, currentPath);
        break;
      case FsUploadAction.fromFiles:
        await _handlePickFiles(device, currentPath);
        break;
      case FsUploadAction.newFolder:
        await _handleMkdir(device, currentPath);
        break;
    }
  }

  /// T-012: handle picking media files for upload.
  Future<void> _handlePickMedia(Device device, String remotePath) async {
    final paths = await pickMediaForUpload(context);
    if (paths == null || paths.isEmpty || !mounted) return;

    // Enqueue files for upload
    await ref
        .notifier(fsUploadProvider)
        .enqueueFiles(
          device: device,
          localPaths: paths,
          remotePath: remotePath,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.fsUpload.uploadingFiles(count: paths.length)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// T-012: handle picking files for upload.
  Future<void> _handlePickFiles(Device device, String remotePath) async {
    final paths = await pickFilesForUpload();
    if (paths == null || paths.isEmpty || !mounted) return;

    // Enqueue files for upload
    await ref
        .notifier(fsUploadProvider)
        .enqueueFiles(
          device: device,
          localPaths: paths,
          remotePath: remotePath,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.fsUpload.uploadingFiles(count: paths.length)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// T-012: handle creating a new folder.
  Future<void> _handleMkdir(Device device, String remotePath) async {
    final folderName = await showMkdirDialog(context);
    if (folderName == null || !mounted) return;

    // Build full remote path
    final newFolderPath = '$remotePath/$folderName';

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.fsUpload.creatingFolder),
        duration: const Duration(seconds: 30),
      ),
    );

    try {
      // Call mkdir via Rust client with certificate
      final protocol = device.https ? rust.ProtocolType.https : rust.ProtocolType.http;
      final ip = device.ip;
      if (ip == null) {
        throw Exception('Device has no IP address');
      }

      final securityContext = ref.read(securityProvider);
      final client = rust_http.createClient(
        privateKey: securityContext.privateKey,
        cert: securityContext.certificate,
        version: rust_http.LsHttpClientVersion.v2,
        expectedFingerprint: device.fingerprint,
        timeoutMs: 30000,
      );
      await client.fsMkdir(
        protocol: protocol,
        ip: ip,
        port: device.port,
        path: newFolderPath,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.fsUpload.folderCreated),
          duration: const Duration(seconds: 2),
        ),
      );

      // Refresh the file list
      ref.notifier(fsListProvider).refresh(device);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.fsUpload.uploadFailed),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// T-016: 多选模式下点击条目
  void _onTapEntryInMultiSelect(Device device, FsListState state, rust.FsEntry entry) {
    final fullPath = state.currentPath.isEmpty ? entry.name : '${state.currentPath}/${entry.name}';
    ref.notifier(fsMutationProvider).toggleSelection(fullPath);
  }

  /// T-016: 长按条目弹上下文菜单
  void _onLongPressEntry(Device device, FsListState state, rust.FsEntry entry) async {
    debugPrint('[T-016 DEBUG] _onLongPressEntry called for: ${entry.name}');
    final fullPath = state.currentPath.isEmpty ? entry.name : '${state.currentPath}/${entry.name}';

    debugPrint('[T-016 DEBUG] Full path: $fullPath');

    // 显示上下文菜单
    final action = await FsContextMenu.show(
      context: context,
      entry: entry,
    );

    if (action == null || !mounted) return;

    debugPrint('[T-016 DEBUG] Selected action: $action');

    switch (action) {
      case FsContextAction.rename:
        await _handleRename(device, fullPath, entry.name, entry.isDir);
        break;
      case FsContextAction.move:
        await _handleMoveSingle(device, fullPath);
        break;
      case FsContextAction.delete:
        await _handleDeleteSingle(device, fullPath);
        break;
      case FsContextAction.share:
        _handleShare(entry);
        break;
      case FsContextAction.properties:
        await _handleProperties(device, fullPath);
        break;
    }
  }

  /// T-016: 显示移动对话框
  Future<void> _showMoveDialog(Device device, FsMutationData mutationState) async {
    final targetPath = await showMoveTargetPicker(
      context: context,
      device: device,
      excludedPaths: mutationState.selectedPaths.toList(),
    );

    if (targetPath == null || !mounted) return;

    // 执行移动操作
    await ref
        .notifier(fsMutationProvider)
        .moveAsync(
          device: device,
          paths: mutationState.selectedPaths.toList(),
          targetDir: targetPath,
        );

    // 检查操作结果
    if (!mounted) return;
    final newState = ref.read(fsMutationProvider);
    if (newState.state == FsMutationState.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('移动成功'),
          duration: Duration(seconds: 2),
        ),
      );
      // 刷新文件列表
      ref.notifier(fsListProvider).refresh(device);
    } else if (newState.state == FsMutationState.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('移动失败: ${newState.errorMessage}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// T-016: 显示删除对话框
  Future<void> _showDeleteDialog(Device device, FsMutationData mutationState) async {
    final useRecycleBin = await showDeleteConfirmDialog(
      context: context,
      itemCount: mutationState.selectedPaths.length,
    );

    if (useRecycleBin == null || !mounted) return;

    // 执行删除操作
    await ref
        .notifier(fsMutationProvider)
        .deleteAsync(
          device: device,
          paths: mutationState.selectedPaths.toList(),
          useRecycleBin: useRecycleBin,
        );

    // 检查操作结果
    if (!mounted) return;
    final newState = ref.read(fsMutationProvider);
    if (newState.state == FsMutationState.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('删除成功'),
          duration: Duration(seconds: 2),
        ),
      );
      // 刷新文件列表
      ref.notifier(fsListProvider).refresh(device);
    } else if (newState.state == FsMutationState.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败: ${newState.errorMessage}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// T-016: 处理重命名操作
  Future<void> _handleRename(Device device, String fullPath, String currentName, bool isDir) async {
    final newName = await showRenameDialog(
      context: context,
      currentName: currentName,
      isDirectory: isDir,
    );

    if (newName == null || !mounted) return;

    await ref
        .notifier(fsMutationProvider)
        .renameAsync(
          device: device,
          oldPath: fullPath,
          newName: newName,
        );

    if (!mounted) return;
    final newState = ref.read(fsMutationProvider);
    if (newState.state == FsMutationState.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('重命名成功'),
          duration: Duration(seconds: 2),
        ),
      );
      ref.notifier(fsListProvider).refresh(device);
    } else if (newState.state == FsMutationState.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重命名失败: ${newState.errorMessage}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// T-016: 处理单个文件移动
  Future<void> _handleMoveSingle(Device device, String fullPath) async {
    await _showMoveDialog(
      device,
      FsMutationData(
        state: FsMutationState.idle,
        selectedPaths: {fullPath},
        isMultiSelectMode: true,
      ),
    );
  }

  /// T-016: 处理单个文件删除
  Future<void> _handleDeleteSingle(Device device, String fullPath) async {
    await _showDeleteDialog(
      device,
      FsMutationData(
        state: FsMutationState.idle,
        selectedPaths: {fullPath},
        isMultiSelectMode: true,
      ),
    );
  }

  /// T-016: 处理分享操作
  void _handleShare(rust.FsEntry entry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('分享功能开发中...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// T-016: 处理属性查看
  Future<void> _handleProperties(Device device, String fullPath) async {
    try {
      final securityContext = ref.read(securityProvider);
      final client = rust_http.createClient(
        privateKey: securityContext.privateKey,
        cert: securityContext.certificate,
        version: rust_http.LsHttpClientVersion.v2,
        expectedFingerprint: device.fingerprint,
        timeoutMs: 30000,
      );
      final protocol = device.https ? rust.ProtocolType.https : rust.ProtocolType.http;
      final ip = device.ip;
      if (ip == null) {
        throw Exception('Device has no IP address');
      }

      final stat = await client.fsStat(
        protocol: protocol,
        ip: ip,
        port: device.port,
        path: fullPath,
      );

      if (!mounted) return;

      // 显示属性对话框
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('文件属性'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _propertyRow('名称', stat.name),
              _propertyRow('类型', stat.isDir ? '文件夹' : '文件'),
              _propertyRow('大小', stat.isDir ? '—' : _formatBytes(stat.size)),
              _propertyRow('修改时间', _formatTime(stat.mtime)),
              _propertyRow('MIME', stat.mime ?? '未知'),
              _propertyRow('ETag', stat.etag),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('获取属性失败: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _propertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(BigInt bytes) {
    final kb = BigInt.from(1024);
    final mb = kb * kb;
    final gb = mb * kb;
    if (bytes < kb) return '${bytes.toString()} B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / gb).toStringAsFixed(2)} GB';
  }

  String _formatTime(int epochSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
