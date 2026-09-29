import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust_http;
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('FsMutation');

/// 操作状态
enum FsMutationState {
  idle,
  loading,
  success,
  error,
}

/// 操作类型
enum FsMutationType {
  rename,
  move,
  delete,
}

/// 变更状态数据
class FsMutationData {
  final FsMutationState state;
  final FsMutationType? operationType;
  final Set<String> selectedPaths;
  final bool isMultiSelectMode;
  final String? errorMessage;
  final List<rust_model.FsEntry>? snapshotBeforeMutation;

  const FsMutationData({
    required this.state,
    this.operationType,
    required this.selectedPaths,
    required this.isMultiSelectMode,
    this.errorMessage,
    this.snapshotBeforeMutation,
  });

  factory FsMutationData.initial() => const FsMutationData(
        state: FsMutationState.idle,
        selectedPaths: {},
        isMultiSelectMode: false,
      );

  FsMutationData copyWith({
    FsMutationState? state,
    FsMutationType? operationType,
    Set<String>? selectedPaths,
    bool? isMultiSelectMode,
    String? errorMessage,
    List<rust_model.FsEntry>? snapshotBeforeMutation,
    bool clearError = false,
    bool clearSnapshot = false,
  }) {
    return FsMutationData(
      state: state ?? this.state,
      operationType: operationType ?? this.operationType,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      isMultiSelectMode: isMultiSelectMode ?? this.isMultiSelectMode,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      snapshotBeforeMutation: clearSnapshot
          ? null
          : (snapshotBeforeMutation ?? this.snapshotBeforeMutation),
    );
  }
}

final fsMutationProvider = NotifierProvider<FsMutationNotifier, FsMutationData>(
  (ref) => FsMutationNotifier(),
);

class FsMutationNotifier extends Notifier<FsMutationData> {
  @override
  FsMutationData init() => FsMutationData.initial();

  /// 进入多选模式
  void enterMultiSelect(String initialPath) {
    state = state.copyWith(
      isMultiSelectMode: true,
      selectedPaths: {initialPath},
    );
  }

  /// 切换选择状态
  void toggleSelection(String path) {
    final newSelection = Set<String>.from(state.selectedPaths);
    if (newSelection.contains(path)) {
      newSelection.remove(path);
      // 如果没有选择了，退出多选模式
      if (newSelection.isEmpty) {
        exitMultiSelect();
        return;
      }
    } else {
      newSelection.add(path);
    }
    state = state.copyWith(selectedPaths: newSelection);
  }

  /// 退出多选模式
  void exitMultiSelect() {
    state = FsMutationData.initial();
  }

  /// 重命名操作
  Future<void> renameAsync({
    required Device device,
    required String oldPath,
    required String newName,
  }) async {
    state = state.copyWith(
      state: FsMutationState.loading,
      operationType: FsMutationType.rename,
      clearError: true,
    );

    try {
      // 构建新路径
      final parentPath = oldPath.contains('/')
          ? oldPath.substring(0, oldPath.lastIndexOf('/'))
          : '';
      final newPath = parentPath.isEmpty ? newName : '$parentPath/$newName';

      final client = rust_http.createHttpOnlyClient();
      final protocol = device.https
          ? rust_model.ProtocolType.https
          : rust_model.ProtocolType.http;
      final ip = device.ip;
      if (ip == null) {
        throw Exception('Device has no IP address');
      }

      await client.fsMove(
        protocol: protocol,
        ip: ip,
        port: device.port,
        from: oldPath,
        to: newPath,
      );

      _logger.info('Renamed $oldPath to $newPath');

      state = state.copyWith(
        state: FsMutationState.success,
        operationType: FsMutationType.rename,
        isMultiSelectMode: false,
        selectedPaths: {},
      );
    } catch (e, st) {
      _logger.warning('Rename failed', e, st);
      state = state.copyWith(
        state: FsMutationState.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 移动操作
  Future<void> moveAsync({
    required Device device,
    required List<String> paths,
    required String targetDir,
  }) async {
    state = state.copyWith(
      state: FsMutationState.loading,
      operationType: FsMutationType.move,
      clearError: true,
    );

    try {
      final client = rust_http.createHttpOnlyClient();
      final protocol =
          device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http;
      final ip = device.ip;
      if (ip == null) {
        throw Exception('Device has no IP address');
      }

      // 逐个移动
      for (final path in paths) {
        final filename = path.contains('/')
            ? path.substring(path.lastIndexOf('/') + 1)
            : path;
        final newPath = '$targetDir/$filename';

        await client.fsMove(
          protocol: protocol,
          ip: ip,
          port: device.port,
          from: path,
          to: newPath,
        );
      }

      _logger.info('Moved ${paths.length} items to $targetDir');

      state = state.copyWith(
        state: FsMutationState.success,
        operationType: FsMutationType.move,
        isMultiSelectMode: false,
        selectedPaths: {},
      );
    } catch (e, st) {
      _logger.warning('Move failed', e, st);
      state = state.copyWith(
        state: FsMutationState.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 删除操作
  Future<void> deleteAsync({
    required Device device,
    required List<String> paths,
    bool useRecycleBin = true,
  }) async {
    state = state.copyWith(
      state: FsMutationState.loading,
      operationType: FsMutationType.delete,
      clearError: true,
    );

    try {
      final client = rust_http.createHttpOnlyClient();
      final protocol =
          device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http;
      final ip = device.ip;
      if (ip == null) {
        throw Exception('Device has no IP address');
      }

      final response = await client.fsDelete(
        protocol: protocol,
        ip: ip,
        port: device.port,
        paths: paths,
        recycle: useRecycleBin,
      );

      _logger.info(
          'Deleted ${response.deleted.length} items, ${response.failed.length} failed');

      if (response.failed.isNotEmpty) {
        final failedPaths = response.failed.map((f) => f.path).join(', ');
        state = state.copyWith(
          state: FsMutationState.error,
          errorMessage: 'Failed to delete: $failedPaths',
          isMultiSelectMode: false,
          selectedPaths: {},
        );
        return;
      }

      state = state.copyWith(
        state: FsMutationState.success,
        operationType: FsMutationType.delete,
        isMultiSelectMode: false,
        selectedPaths: {},
      );
    } catch (e, st) {
      _logger.warning('Delete failed', e, st);
      state = state.copyWith(
        state: FsMutationState.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(
      state: FsMutationState.idle,
      clearError: true,
    );
  }
}
