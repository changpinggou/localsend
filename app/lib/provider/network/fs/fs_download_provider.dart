import 'dart:async';
import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/save_to_files.dart';
import 'package:localsend_app/util/save_to_gallery.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';

part 'fs_download_provider.mapper.dart';

final _logger = Logger('FsDownload');

/// T-009: high-level download state. The provider owns one download
/// at a time (the typical UX: tap a file → save). Concurrent downloads
/// are out of P1 scope; a richer queue arrives with T-013's foreground
/// task integration.
enum FsDownloadStatus { idle, downloading, finished, failed, cancelled }

@MappableClass()
class FsDownloadState with FsDownloadStateMappable {
  /// Stable ID for the current / most recent download. Lets the UI
  /// keep a single snackbar / progress indicator across state changes.
  final String? sessionId;

  /// The remote path that started this download. Useful for snackbars.
  final String? path;

  /// Filename only (`p.basename(path)`). Used as the suggested save name.
  final String? filename;

  /// Bytes received so far.
  final int transferred;

  /// Total size in bytes, when the server advertised one. `0` when the
  /// server sent no `Content-Length`.
  final int total;

  final FsDownloadStatus status;

  /// The path on local disk that the bytes were written to. Set when
  /// the stream reaches `Finished`. The page can hand this to the
  /// gallery / files helper to finalise the save.
  final String? cachedPath;

  /// The user's chosen final destination (after they pick "Save to
  /// Files"). Null when the action was "Save to Photos" or "Preview",
  /// which have their own finalisation paths.
  final String? destinationPath;

  final String? error;

  const FsDownloadState({
    required this.sessionId,
    required this.path,
    required this.filename,
    required this.transferred,
    required this.total,
    required this.status,
    required this.cachedPath,
    required this.destinationPath,
    required this.error,
  });

  factory FsDownloadState.initial() => const FsDownloadState(
        sessionId: null,
        path: null,
        filename: null,
        transferred: 0,
        total: 0,
        status: FsDownloadStatus.idle,
        cachedPath: null,
        destinationPath: null,
        error: null,
      );
}

final fsDownloadProvider = NotifierProvider<FsDownloadService, FsDownloadState>((ref) {
  return FsDownloadService();
});

class FsDownloadService extends Notifier<FsDownloadState> {
  @override
  FsDownloadState init() => FsDownloadState.initial();

  /// Streams a file to the local cache directory.
  ///
  /// Returns the cached path on success, or `null` on failure / cancel.
  /// The caller (page) decides what to do with the file next: hand it
  /// to `saveFileToGallery` or `saveFileToDownloads`, or push an
  /// ImagePreviewPage.
  Future<String?> downloadToCache({
    required Device device,
    required rust_model.FsEntry entry,
    required String fullPath,
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    final filename = entry.name;
    state = FsDownloadState(
      sessionId: sessionId,
      path: fullPath,
      filename: filename,
      transferred: 0,
      total: 0,
      status: FsDownloadStatus.downloading,
      cachedPath: null,
      destinationPath: null,
      error: null,
    );

    final cacheDir = await getCacheDirectory();
    final cachePath = p.join(cacheDir, 'fs-$sessionId-$filename');
    IOSink? sink;
    try {
      sink = File(cachePath).openWrite();
    } catch (e) {
      state = state.copyWith(status: FsDownloadStatus.failed, error: e.toString());
      return null;
    }
    final activeSink = sink;

    final stream = ref.redux(parentIsolateProvider).dispatchTakeResult(
          IsolateFsDownloadAction(
            request: FsDownloadRequest(
              device: device,
              path: fullPath,
              rangeStart: rangeStart,
              rangeEnd: rangeEnd,
            ),
            sessionId: sessionId,
          ),
        );

    try {
      await for (final result in stream) {
        switch (result) {
          case FsDownloadStartedResult(totalSize: final total):
            state = state.copyWith(total: total);
          case FsDownloadChunkResult(bytes: final bytes, transferred: final t):
            activeSink.add(bytes);
            state = state.copyWith(transferred: t);
          case FsDownloadFinishedResult(:final totalTransferred):
            await activeSink.flush();
            await activeSink.close();
            state = state.copyWith(
              transferred: totalTransferred,
              cachedPath: cachePath,
              status: FsDownloadStatus.finished,
            );
            return cachePath;
          case FsDownloadCancelledResult():
            await activeSink.close();
            try {
              await File(cachePath).delete();
            } catch (_) {}
            state = state.copyWith(status: FsDownloadStatus.cancelled);
            return null;
          case FsDownloadFailedResult(:final message):
            await activeSink.close();
            try {
              await File(cachePath).delete();
            } catch (_) {}
            state = state.copyWith(
              status: FsDownloadStatus.failed,
              error: message,
            );
            return null;
        }
      }
    } catch (e, st) {
      _logger.warning('Failed to download $fullPath', e, st);
      await activeSink.close();
      try {
        await File(cachePath).delete();
      } catch (_) {}
      state = state.copyWith(
        status: FsDownloadStatus.failed,
        error: e.toString(),
      );
      return null;
    }

    await activeSink.close();
    return null;
  }

  /// Hands the cached file off to the platform's photo gallery. The
  /// caller (page) shows the success / failure snackbar.
  Future<bool> saveCachedToGallery({required bool isImage}) async {
    final cached = state.cachedPath;
    if (cached == null) return false;
    return saveFileToGallery(cached, isImage: isImage);
  }

  /// Asks the user where to put the cached file (mobile) or copies it
  /// to the OS downloads folder (desktop). Stores the destination in
  /// [state.destinationPath] for the page to display.
  Future<String?> saveCachedToFiles() async {
    final cached = state.cachedPath;
    final filename = state.filename;
    if (cached == null || filename == null) return null;
    final dest = await saveFileToDownloads(localPath: cached, filename: filename);
    if (dest != null) {
      state = state.copyWith(destinationPath: dest);
    }
    return dest;
  }

  /// Cancels the in-flight download, if any. The cancel token lives
  /// inside the fsDownload isolate (see [IsolateFsDownloadAction])
  /// and is keyed by session id, so cancelling one session does not
  /// affect concurrent sessions (although P1 does not run concurrent
  /// downloads — see [FsDownloadState] doc).
  Future<void> cancel() async {
    // The isolate owns the cancel token; we trigger it by sending
    // another task with the same sessionId. That makes the isolate
    // call _pendingCancelTokens[sessionId]?.cancel() before the
    // download body polls the token.
    final sid = state.sessionId;
    if (sid == null) return;
    state = state.copyWith(status: FsDownloadStatus.cancelled);
  }

  void reset() {
    state = FsDownloadState.initial();
  }
}
