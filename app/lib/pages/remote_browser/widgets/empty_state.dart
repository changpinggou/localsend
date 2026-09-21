import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';

/// T-008: empty state for a directory listing or the roots level when
/// the device has no whitelisted drives.
class FsEmptyState extends StatelessWidget {
  final bool isRoots;
  final VoidCallback? onRetry;

  const FsEmptyState({required this.isRoots, this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRoots ? Icons.storage_outlined : Icons.folder_open_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              isRoots ? t.remoteBrowser.roots : t.remoteBrowser.emptyFolder,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(t.remoteBrowser.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// T-008: error state for failed fetches. Replaces the body with a
/// retryable error card; on tap of retry the parent reissues the request.
class FsErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const FsErrorState({required this.message, required this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              t.remoteBrowser.errorTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message ?? t.remoteBrowser.errorGeneric,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(t.remoteBrowser.retry),
            ),
          ],
        ),
      ),
    );
  }
}

/// T-008: skeleton list rendered while a fetch is in-flight and no
/// previous entries are available to show.
class FsLoadingSkeleton extends StatelessWidget {
  final int rows;
  const FsLoadingSkeleton({this.rows = 10, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      itemCount: rows,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
