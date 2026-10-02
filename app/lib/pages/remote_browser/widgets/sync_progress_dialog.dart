import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/fs/photo_sync_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Modal dialog showing photo sync progress.
///
/// Displays three phases:
///   1. Scanning local library
///   2. Scanning remote directory
///   3. Uploading new/modified files
///
/// Auto-closes when sync completes or fails.
class SyncProgressDialog extends StatefulWidget {
  final int localCount;
  final int remoteCount;
  final int toUploadCount;

  const SyncProgressDialog({
    required this.localCount,
    required this.remoteCount,
    required this.toUploadCount,
    super.key,
  });

  static Future<void> show({
    required BuildContext context,
    required int localCount,
    required int remoteCount,
    required int toUploadCount,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Photo Sync',
      pageBuilder: (ctx, anim1, anim2) => SyncProgressDialog(
        localCount: localCount,
        remoteCount: remoteCount,
        toUploadCount: toUploadCount,
      ),
    );
  }

  @override
  State<SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<SyncProgressDialog> with Refena {
  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(photoSyncProvider);

    return AlertDialog(
      title: Text(t.sync.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPhaseInfo(syncState),
            const SizedBox(height: 16),
            _buildProgress(syncState),
          ],
        ),
      ),
      actions: [
        if (syncState.phase == PhotoSyncPhase.done || syncState.phase == PhotoSyncPhase.failed)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.general.close),
          ),
      ],
    );
  }

  Widget _buildPhaseInfo(PhotoSyncState state) {
    final theme = Theme.of(context);
    switch (state.phase) {
      case PhotoSyncPhase.scanningLocal:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.sync.scanningLocal, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${t.sync.scanned}: ${state.localScannedCount}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        );
      case PhotoSyncPhase.scanningRemote:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.sync.scanningRemote, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${t.sync.scanned}: ${state.remoteScannedCount}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        );
      case PhotoSyncPhase.comparing:
        return Text(t.sync.comparing, style: theme.textTheme.titleSmall);
      case PhotoSyncPhase.uploading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.sync.uploading, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (state.currentFilename != null)
              Text(
                state.currentFilename!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
          ],
        );
      case PhotoSyncPhase.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 32),
            const SizedBox(height: 8),
            Text(
              '${t.sync.uploaded}: ${state.uploadedCount}\n'
              '${t.sync.skipped}: ${state.skippedCount}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        );
      case PhotoSyncPhase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error, color: theme.colorScheme.error, size: 32),
            const SizedBox(height: 8),
            Text(state.error ?? 'Unknown error', style: theme.textTheme.bodyMedium),
          ],
        );
      case PhotoSyncPhase.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProgress(PhotoSyncState state) {
    switch (state.phase) {
      case PhotoSyncPhase.scanningLocal:
      case PhotoSyncPhase.scanningRemote:
      case PhotoSyncPhase.comparing:
        return const LinearProgressIndicator();
      case PhotoSyncPhase.uploading:
        if (state.totalToUpload == 0) return const SizedBox.shrink();
        final progress = state.uploadedCount / state.totalToUpload;
        return Column(
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text(
              '${state.uploadedCount} / ${state.totalToUpload}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case PhotoSyncPhase.done:
      case PhotoSyncPhase.failed:
      case PhotoSyncPhase.idle:
        return const SizedBox.shrink();
    }
  }
}
