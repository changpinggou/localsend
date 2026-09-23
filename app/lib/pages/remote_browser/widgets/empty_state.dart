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
///
/// The optional [reason] tag lets the page pick a more specific subtitle
/// for known failure modes (404 from a peer that didn't enable fs, 403
/// from a peer that didn't whitelist the path, timeout when the peer
/// is offline, etc.). When [reason] is null the message falls back to
/// the caller-supplied [message] or the generic "try again" copy.
class FsErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;
  final FsErrorReason? reason;

  const FsErrorState({
    required this.onRetry,
    this.message,
    this.reason,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, body) = switch (reason) {
      FsErrorReason.fsDisabledByPeer => (
        Icons.lock_outline,
        t.fsBrowser.fsDisabledByPeerTitle,
        t.fsBrowser.fsDisabledByPeerBody,
      ),
      FsErrorReason.notFound => (
        Icons.help_outline,
        t.fsBrowser.notFoundTitle,
        t.fsBrowser.notFoundBody,
      ),
      FsErrorReason.timeout => (
        Icons.wifi_off,
        t.fsBrowser.timeoutTitle,
        t.fsBrowser.timeoutBody,
      ),
      FsErrorReason.pathDenied => (
        Icons.block,
        t.fsBrowser.pathDeniedTitle,
        t.fsBrowser.pathDeniedBody,
      ),
      FsErrorReason.network => (
        Icons.cloud_off,
        t.fsBrowser.networkTitle,
        t.fsBrowser.networkBody,
      ),
      null => (
        Icons.error_outline,
        t.remoteBrowser.errorTitle,
        message ?? t.remoteBrowser.errorGeneric,
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
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

/// T-008 follow-up: structured error reasons so the page can pick a
/// user-readable message instead of dumping `RsHttpClientError` to
/// the screen. New variants get added as we discover new failure
/// modes.
enum FsErrorReason {
  /// HTTP 404 — the peer didn't enable the `fs` capability, or it's
  /// running on plain HTTP (T-005 requires HTTPS for the fs namespace).
  fsDisabledByPeer,

  /// Generic HTTP 404 from a non-fs endpoint.
  notFound,

  /// The request timed out (peer unreachable or slow).
  timeout,

  /// HTTP 403 — the path was outside the peer's whitelist (T-004).
  pathDenied,

  /// Network-level failure (DNS, refused connection, etc.).
  network,
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
