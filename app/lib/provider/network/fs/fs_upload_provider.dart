import 'dart:async';
import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';

part 'fs_upload_provider.mapper.dart';

final _logger = Logger('FsUpload');

/// T-012: upload queue item status.
enum FsUploadStatus {
  /// Waiting in the queue, not yet started.
  queued,

  /// Actively uploading.
  uploading,

  /// Temporarily paused by the user.
  paused,

  /// Completed successfully.
  finished,

  /// Failed with an error.
  failed,

  /// Cancelled by the user.
  cancelled,
}

/// T-012: a single file in the upload queue.
@MappableClass()
class FsUploadTask with FsUploadTaskMappable {
  /// Stable session ID for resume/cancel.
  final String sessionId;

  /// Local file path on the mobile device.
  final String localPath;

  /// Filename only (`p.basename(localPath)`).
  final String filename;

  /// Remote directory path on the peer (e.g., "Photos/2024").
  final String remotePath;

  /// Total file size in bytes.
  final int total;

  /// Bytes uploaded so far.
  final int transferred;

  /// Current status.
  final FsUploadStatus status;

  /// Error message when status == failed.
  final String? error;

  /// The peer device we're uploading to.
  final Device device;

  const FsUploadTask({
    required this.sessionId,
    required this.localPath,
    required this.filename,
    required this.remotePath,
    required this.total,
    required this.transferred,
    required this.status,
    required this.error,
    required this.device,
  });
}

/// T-012: upload queue state. Manages multiple concurrent uploads.
@MappableClass()
class FsUploadState with FsUploadStateMappable {
  /// All tasks in the queue, in insertion order.
  final List<FsUploadTask> tasks;

  const FsUploadState({required this.tasks});

  factory FsUploadState.initial() => const FsUploadState(tasks: []);

  /// Number of tasks currently uploading.
  int get activeCount => tasks.where((t) => t.status == FsUploadStatus.uploading).length;

  /// Number of tasks waiting in the queue.
  int get queuedCount => tasks.where((t) => t.status == FsUploadStatus.queued).length;

  /// Number of tasks that finished successfully.
  int get finishedCount => tasks.where((t) => t.status == FsUploadStatus.finished).length;

  /// Number of tasks that failed.
  int get failedCount => tasks.where((t) => t.status == FsUploadStatus.failed).length;

  /// Total bytes to upload across all tasks.
  int get totalBytes => tasks.fold(0, (sum, t) => sum + t.total);

  /// Total bytes uploaded so far.
  int get transferredBytes => tasks.fold(0, (sum, t) => sum + t.transferred);
}

final fsUploadProvider = NotifierProvider<FsUploadService, FsUploadState>((ref) {
  return FsUploadService();
});

class FsUploadService extends Notifier<FsUploadState> {
  /// Maximum concurrent uploads. P2 spec says 2–4; we use 2 to avoid
  /// overwhelming the peer's I/O.
  static const int maxConcurrent = 2;

  @override
  FsUploadState init() => FsUploadState.initial();

  /// T-012: enqueue a batch of files for upload.
  ///
  /// Each file gets a unique session ID. The isolate will process them
  /// up to [maxConcurrent] at a time.
  Future<void> enqueueFiles({
    required Device device,
    required List<String> localPaths,
    required String remotePath,
  }) async {
    final newTasks = <FsUploadTask>[];

    for (final localPath in localPaths) {
      final file = File(localPath);
      if (!await file.exists()) {
        _logger.warning('File does not exist: $localPath');
        continue;
      }

      final stat = await file.stat();
      final sessionId = _generateSessionId();

      newTasks.add(FsUploadTask(
        sessionId: sessionId,
        localPath: localPath,
        filename: p.basename(localPath),
        remotePath: remotePath,
        total: stat.size,
        transferred: 0,
        status: FsUploadStatus.queued,
        error: null,
        device: device,
      ));
    }

    if (newTasks.isEmpty) {
      return;
    }

    state = state.copyWith(tasks: [...state.tasks, ...newTasks]);
    _logger.info('Enqueued ${newTasks.length} upload tasks');

    // Kick off the worker loop.
    _processQueue();
  }

  /// T-012: pause a specific upload task.
  void pauseTask(String sessionId) {
    final index = state.tasks.indexWhere((t) => t.sessionId == sessionId);
    if (index == -1) return;

    final task = state.tasks[index];
    if (task.status != FsUploadStatus.uploading && task.status != FsUploadStatus.queued) {
      return;
    }

    // Cancel the isolate task (it will clean up the temp file on the peer).
    _cancelIsolateTask(sessionId);

    final updated = task.copyWith(status: FsUploadStatus.paused);
    final newTasks = List<FsUploadTask>.from(state.tasks);
    newTasks[index] = updated;
    state = state.copyWith(tasks: newTasks);

    _logger.info('Paused upload task $sessionId');
  }

  /// T-012: resume a paused upload task.
  Future<void> resumeTask(String sessionId) async {
    final index = state.tasks.indexWhere((t) => t.sessionId == sessionId);
    if (index == -1) return;

    final task = state.tasks[index];
    if (task.status != FsUploadStatus.paused) {
      return;
    }

    final updated = task.copyWith(status: FsUploadStatus.queued);
    final newTasks = List<FsUploadTask>.from(state.tasks);
    newTasks[index] = updated;
    state = state.copyWith(tasks: newTasks);

    _logger.info('Resumed upload task $sessionId');

    // Kick off the worker loop.
    _processQueue();
  }

  /// T-012: cancel a specific upload task.
  void cancelTask(String sessionId) {
    final index = state.tasks.indexWhere((t) => t.sessionId == sessionId);
    if (index == -1) return;

    final task = state.tasks[index];
    if (task.status == FsUploadStatus.finished || task.status == FsUploadStatus.cancelled) {
      return;
    }

    // Cancel the isolate task.
    _cancelIsolateTask(sessionId);

    final updated = task.copyWith(status: FsUploadStatus.cancelled);
    final newTasks = List<FsUploadTask>.from(state.tasks);
    newTasks[index] = updated;
    state = state.copyWith(tasks: newTasks);

    // Stop foreground notification for this upload
    TransferNotification.stop(sessionId);

    _logger.info('Cancelled upload task $sessionId');
  }

  /// T-012: remove finished/failed/cancelled tasks from the queue.
  void clearCompleted() {
    final remaining = state.tasks.where((t) {
      return t.status != FsUploadStatus.finished &&
          t.status != FsUploadStatus.failed &&
          t.status != FsUploadStatus.cancelled;
    }).toList();

    state = state.copyWith(tasks: remaining);
    _logger.info('Cleared completed uploads, ${remaining.length} remaining');
  }

  /// T-012: reset the entire queue.
  void reset() {
    state = FsUploadState.initial();
    _logger.info('Upload queue reset');
  }

  /// Process the queue: start uploads up to [maxConcurrent].
  void _processQueue() {
    if (state.activeCount >= maxConcurrent) {
      return;
    }

    for (final task in state.tasks) {
      if (state.activeCount >= maxConcurrent) {
        break;
      }

      if (task.status == FsUploadStatus.queued) {
        unawaited(_startUpload(task));
      }
    }
  }

  /// Start a single upload task via the isolate.
  Future<void> _startUpload(FsUploadTask task) async {
    final index = state.tasks.indexWhere((t) => t.sessionId == task.sessionId);
    if (index == -1) return;

    // Mark as uploading.
    final updated = task.copyWith(status: FsUploadStatus.uploading);
    final newTasks = List<FsUploadTask>.from(state.tasks);
    newTasks[index] = updated;
    state = state.copyWith(tasks: newTasks);

    _logger.info('Starting upload: ${task.filename} → ${task.remotePath}');

    // Start foreground notification for this upload
    TransferNotification.start(sessionId: task.sessionId, receiving: false);

    try {
      final request = FsUploadRequest(
        device: task.device,
        localPath: task.localPath,
        remotePath: task.remotePath,
      );
      final result = ref.redux(parentIsolateProvider).dispatchTakeResult(
            IsolateFsUploadAction(
              sessionId: task.sessionId,
              request: request,
            ),
          );

      await for (final event in result) {
        if (event is FsUploadProgressEvent) {
          _updateProgress(task.sessionId, event.transferred);
          // Update foreground notification with progress
          TransferNotification.update(
            sessionId: task.sessionId,
            currentBytes: event.transferred,
            totalBytes: task.total,
            startTime: null, // TODO: track start time for speed calculation
            endTime: null,
          );
        } else if (event is FsUploadFinishedEvent) {
          _markFinished(task.sessionId);
          TransferNotification.stop(task.sessionId);
          _processQueue();
          return;
        } else if (event is FsUploadFailedEvent) {
          _markFailed(task.sessionId, event.error);
          TransferNotification.stop(task.sessionId);
          _processQueue();
          return;
        } else if (event is FsUploadCancelledEvent) {
          _markCancelled(task.sessionId);
          TransferNotification.stop(task.sessionId);
          _processQueue();
          return;
        }
      }
    } catch (e, st) {
      _logger.severe('Upload failed: ${task.filename}', e, st);
      TransferNotification.stop(task.sessionId);
      _markFailed(task.sessionId, e.toString());
      _processQueue();
    }
  }

  /// Cancel the isolate task for a session.
  void _cancelIsolateTask(String sessionId) {
    try {
      ref.redux(parentIsolateProvider).dispatch(
            IsolateFsUploadCancelAction(sessionId: sessionId),
          );
    } catch (e, st) {
      _logger.warning('Failed to cancel isolate task $sessionId', e, st);
    }
  }

  /// Update the progress for a task.
  void _updateProgress(String sessionId, int transferred) {
    final index = state.tasks.indexWhere((t) => t.sessionId == sessionId);
    if (index == -1) return;

    final task = state.tasks[index];
    final updated = task.copyWith(transferred: transferred);
    final newTasks = List<FsUploadTask>.from(state.tasks);
    newTasks[index] = updated;
    state = state.copyWith(tasks: newTasks);
  }

  /// Mark a task as finished.
  void _markFinished(String sessionId) {
    final index = state.tasks.indexWhere((t) => t.sessionId == sessionId);
    if (index == -1) return;

    final task = state.tasks[index];
    final updated = task.copyWith(status: FsUploadStatus.finished, transferred: task.total);
    final newTasks = List<FsUploadTask>.from(state.tasks);
    newTasks[index] = updated;
    state = state.copyWith(tasks: newTasks);

    _logger.info('Upload finished: ${task.filename}');
  }

  /// Mark a task as failed.
  void _markFailed(String sessionId, String error) {
    final index = state.tasks.indexWhere((t) => t.sessionId == sessionId);
    if (index == -1) return;

    final task = state.tasks[index];
    final updated = task.copyWith(status: FsUploadStatus.failed, error: error);
    final newTasks = List<FsUploadTask>.from(state.tasks);
    newTasks[index] = updated;
    state = state.copyWith(tasks: newTasks);

    _logger.warning('Upload failed: ${task.filename}: $error');
  }

  /// Mark a task as cancelled.
  void _markCancelled(String sessionId) {
    final index = state.tasks.indexWhere((t) => t.sessionId == sessionId);
    if (index == -1) return;

    final task = state.tasks[index];
    final updated = task.copyWith(status: FsUploadStatus.cancelled);
    final newTasks = List<FsUploadTask>.from(state.tasks);
    newTasks[index] = updated;
    state = state.copyWith(tasks: newTasks);

    _logger.info('Upload cancelled: ${task.filename}');
  }

  /// Generate a unique session ID.
  String _generateSessionId() {
    return 'upload_${DateTime.now().microsecondsSinceEpoch}_${state.tasks.length}';
  }
}
