import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/fs/fs_upload_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// T-012: a compact bar showing upload progress.
///
/// Displays "Uploading X/Y" with a progress indicator. Tapping it
/// expands to show individual task details with pause/cancel buttons.
class FsUploadQueueBar extends StatelessWidget {
  const FsUploadQueueBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref) {
        final state = ref.watch(fsUploadProvider);
        if (state.tasks.isEmpty) {
          return const SizedBox.shrink();
        }

        final active = state.activeCount;
        final total = state.tasks.length;
        final progress = state.totalBytes > 0 ? state.transferredBytes / state.totalBytes : 0.0;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_upload, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.fsUpload.uploadingFiles(count: total),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (active > 0)
                      _StatusChip(
                        icon: Icons.play_arrow,
                        label: '$active ${t.fsUpload.uploading}',
                        color: Colors.blue,
                      ),
                    if (state.queuedCount > 0)
                      _StatusChip(
                        icon: Icons.schedule,
                        label: '${state.queuedCount} ${t.fsUpload.queued}',
                        color: Colors.grey,
                      ),
                    if (state.finishedCount > 0)
                      _StatusChip(
                        icon: Icons.check_circle,
                        label: '${state.finishedCount} ${t.fsUpload.complete}',
                        color: Colors.green,
                      ),
                    if (state.failedCount > 0)
                      _StatusChip(
                        icon: Icons.error,
                        label: '${state.failedCount} ${t.fsUpload.failed}',
                        color: Colors.red,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
