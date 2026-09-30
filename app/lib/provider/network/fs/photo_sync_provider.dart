import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_app/provider/network/fs/fs_upload_provider.dart';
import 'package:localsend_app/provider/security_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust_http;
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

part 'photo_sync_provider.mapper.dart';

final _logger = Logger('PhotoSync');

/// Sync phase for UI progress display.
enum PhotoSyncPhase {
  idle,
  scanningLocal,
  scanningRemote,
  comparing,
  uploading,
  done,
  failed,
}

/// A local photo ready for sync.
class LocalPhoto {
  final String filename;
  final int size;
  final String localPath;

  const LocalPhoto({
    required this.filename,
    required this.size,
    required this.localPath,
  });
}

@MappableClass()
class PhotoSyncState with PhotoSyncStateMappable {
  final PhotoSyncPhase phase;
  final int localScannedCount;
  final int remoteScannedCount;
  final int uploadedCount;
  final int skippedCount;
  final int failedCount;
  final int totalToUpload;
  final String? currentFilename;
  final String? error;

  const PhotoSyncState({
    required this.phase,
    required this.localScannedCount,
    required this.remoteScannedCount,
    required this.uploadedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.totalToUpload,
    this.currentFilename,
    this.error,
  });

  factory PhotoSyncState.initial() => const PhotoSyncState(
        phase: PhotoSyncPhase.idle,
        localScannedCount: 0,
        remoteScannedCount: 0,
        uploadedCount: 0,
        skippedCount: 0,
        failedCount: 0,
        totalToUpload: 0,
      );
}

final photoSyncProvider = NotifierProvider<PhotoSyncService, PhotoSyncState>((ref) {
  return PhotoSyncService();
});

class PhotoSyncService extends Notifier<PhotoSyncState> {
  /// Scan progress callbacks — updated as scanning proceeds so the UI
  /// can show incremental progress instead of a frozen spinner.
  void Function(int count)? onLocalProgress;
  void Function(int count)? onRemoteProgress;

  @override
  PhotoSyncState init() => PhotoSyncState.initial();

  /// Starts a full sync cycle: scan local → scan remote → diff → upload.
  ///
  /// [device] is the target peer. [remoteDir] is the path on the peer
  /// relative to the mount-point root (e.g. `Photos` or `Photos/2024`).
  ///
  /// Returns the number of files uploaded. Throws on fatal errors
  /// (permission denied, device offline); non-fatal per-file failures
  /// are counted in [PhotoSyncState.failedCount].
  Future<int> startSync({
    required Device device,
    required String remoteDir,
  }) async {
    // Reset state.
    state = PhotoSyncState.initial().copyWith(phase: PhotoSyncPhase.scanningLocal);

    try {
      // Phase 1: Scan local photos.
      final localPhotos = await _scanLocalPhotos();
      state = state.copyWith(
        phase: PhotoSyncPhase.scanningRemote,
        localScannedCount: localPhotos.length,
      );

      if (localPhotos.isEmpty) {
        state = state.copyWith(phase: PhotoSyncPhase.done);
        return 0;
      }

      // Phase 2: Scan remote directory.
      final remoteFiles = await _scanRemoteFiles(device, remoteDir);
      state = state.copyWith(
        phase: PhotoSyncPhase.comparing,
        remoteScannedCount: remoteFiles.length,
      );

      // Phase 3: Compute diff.
      final toUpload = _computeDiff(localPhotos, remoteFiles);
      final skippedCount = localPhotos.length - toUpload.length;

      _logger.info(
        'PhotoSync: local=${localPhotos.length}, remote=${remoteFiles.length}, toUpload=$toUpload.length, skip=$skippedCount',
      );

      state = state.copyWith(
        phase: PhotoSyncPhase.uploading,
        totalToUpload: toUpload.length,
        skippedCount: skippedCount,
      );

      if (toUpload.isEmpty) {
        state = state.copyWith(phase: PhotoSyncPhase.done);
        return 0;
      }

      // Phase 4: Upload diff files.
      final uploaded = await _uploadDiff(device, remoteDir, toUpload);
      final failed = toUpload.length - uploaded;

      state = state.copyWith(
        phase: PhotoSyncPhase.done,
        uploadedCount: uploaded,
        failedCount: failed,
      );

      return uploaded;
    } catch (e, st) {
      _logger.severe('PhotoSync: fatal error', e, st);
      state = state.copyWith(phase: PhotoSyncPhase.failed, error: e.toString());
      rethrow;
    }
  }

  /// Enumerates all photos and videos from the device's photo library.
  ///
  /// Uses [PhotoManager] (from `wechat_assets_picker`) which wraps the
  /// platform photo APIs. We paginate through each album with a large
  /// page size to minimise round-trips.
  Future<List<LocalPhoto>> _scanLocalPhotos() async {
    // Request permission first — the picker already does this, but the
    /// sync flow bypasses the picker UI.
    final granted = await PhotoManager.requestPermissionExtend();
    if (!granted.isAuth) {
      throw StateError('Photo library permission not granted');
    }

    final photos = <LocalPhoto>[];
    const pageSize = 300;

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
    );

    for (final path in paths) {
      int page = 0;
      while (true) {
        final assets = await path.getAssetListPaged(
          page: page,
          size: pageSize,
        );
        if (assets.isEmpty) break;

        for (final asset in assets) {
          try {
            final file = await asset.originFile;
            if (file == null) continue;

            photos.add(LocalPhoto(
              filename: await asset.titleAsync,
              size: await file.length(),
              localPath: file.path,
            ));
          } catch (e) {
            _logger.warning('PhotoSync: failed to read asset ${asset.id}: $e');
          }
        }

        onLocalProgress?.call(photos.length);
        page++;
      }
    }

    return photos;
  }

  /// Lists all files in a remote directory, paging until `hasMore` is false.
  Future<List<rust_model.FsEntry>> _scanRemoteFiles(
    Device device,
    String remoteDir,
  ) async {
    final securityContext = ref.read(securityProvider);
    final client = rust_http.createClient(
      privateKey: securityContext.privateKey,
      cert: securityContext.certificate,
      version: rust_http.LsHttpClientVersion.v2,
      expectedFingerprint: device.fingerprint,
      timeoutMs: 30000,
    );

    final protocol =
        device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http;
    final ip = device.ip;
    if (ip == null) {
      throw StateError('Device has no IP address');
    }

    final allFiles = <rust_model.FsEntry>[];
    int page = 0;
    const pageSize = 100;

    while (true) {
      final response = await client.listDir(
        protocol: protocol,
        ip: ip,
        port: device.port,
        path: remoteDir,
        page: page,
        size: pageSize,
        sort: 'name_asc',
      );

      allFiles.addAll(response.entries);
      onRemoteProgress?.call(allFiles.length);

      if (!response.hasMore) break;
      page++;
    }

    return allFiles;
  }

  /// Computes the set of local photos that need uploading.
  ///
  /// A photo needs uploading if:
  ///   - no file with the same name exists on the remote, OR
  ///   - a file with the same name exists but has a different size
  List<LocalPhoto> _computeDiff(
    List<LocalPhoto> local,
    List<rust_model.FsEntry> remote,
  ) {
    // Build a filename → size lookup for remote files (skip directories).
    final remoteMap = <String, int>{};
    for (final entry in remote) {
      if (!entry.isDir) {
        remoteMap[entry.name] = entry.size.toInt();
      }
    }

    return local.where((photo) {
      final remoteSize = remoteMap[photo.filename];
      return remoteSize == null || remoteSize != photo.size;
    }).toList();
  }

  /// Uploads the diff set using the existing upload queue.
  ///
  /// Returns the number of files that completed successfully.
  Future<int> _uploadDiff(
    Device device,
    String remoteDir,
    List<LocalPhoto> toUpload,
  ) async {
    // Collect paths and enqueue them all at once.
    final paths = toUpload.map((p) => p.localPath).toList();

    ref.notifier(fsUploadProvider).enqueueFiles(
      device: device,
      localPaths: paths,
      remotePath: remoteDir,
    );

    // Monitor the upload queue until all our tasks finish.
    var completed = 0;
    final total = toUpload.length;

    // Poll the upload state until all tasks are terminal.
    while (completed < total) {
      await Future.delayed(const Duration(milliseconds: 500));

      final uploadState = ref.read(fsUploadProvider);
      var done = 0;
      var failed = 0;

      // We track by filename since we don't have session IDs here.
      // Match tasks whose filename is in our upload set.
      final uploadFilenames = toUpload.map((p) => p.filename).toSet();

      for (final task in uploadState.tasks) {
        if (!uploadFilenames.contains(task.filename)) continue;
        switch (task.status) {
          case FsUploadStatus.finished:
            done++;
          case FsUploadStatus.failed:
          case FsUploadStatus.cancelled:
            failed++;
          default:
            break;
        }
      }

      completed = done + failed;
      state = state.copyWith(
        uploadedCount: done,
        failedCount: failed,
        currentFilename: done < total ? toUpload[done].filename : null,
      );
    }

    return total - state.failedCount;
  }
}
