import 'package:flutter/material.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;

/// T-008: list-mode entry row used by [RemoteBrowserPage].
///
/// `name / size / mtime` three columns. `onTap` distinguishes folder vs file
/// entries so the parent can either navigate into the directory (folder)
/// or fire the file action sheet (file). Long-press is left to the parent
/// because it owns the selection / context-menu state.
class FsListRow extends StatelessWidget {
  final rust.FsEntry entry;
  final bool isLast;
  final VoidCallback onTap;

  const FsListRow({
    required this.entry,
    required this.isLast,
    required this.onTap,
    super.key,
  });

  /// Used when rendering the roots level (no `FsEntry`, just an `FsRoot`).
  /// Lifted out so the same row widget can render both mount points and
  /// directory entries.
  static Widget rootRow({
    required rust.FsRoot root,
    required bool isLast,
    required VoidCallback onTap,
  }) {
    return _RootRow(root: root, isLast: isLast, onTap: onTap);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              entry.isDir ? Icons.folder : _fileIcon(entry.name),
              color: entry.isDir ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: Text(
                entry.isDir ? '—' : _formatSize(entry.size),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: Text(
                entry.isDir ? '—' : _formatMtime(entry.mtime),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _fileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp') || lower.endsWith('.heic')) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.mkv')) {
      return Icons.movie_outlined;
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.m4a')) {
      return Icons.audiotrack_outlined;
    }
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.endsWith('.zip') || lower.endsWith('.tar') || lower.endsWith('.gz') || lower.endsWith('.7z')) {
      return Icons.archive_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  static String _formatSize(BigInt bytes) {
    final kb = BigInt.from(1024);
    final mb = kb * kb;
    final gb = mb * kb;
    if (bytes < kb) return '${bytes.toString()} B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / gb).toStringAsFixed(2)} GB';
  }

  /// `mtime` is Unix epoch seconds.
  static String _formatMtime(int epochSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
    final now = DateTime.now();
    final isThisYear = dt.year == now.year;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
        '${isThisYear ? '' : ' ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'}';
  }
}

class _RootRow extends StatelessWidget {
  final rust.FsRoot root;
  final bool isLast;
  final VoidCallback onTap;

  const _RootRow({
    required this.root,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              root.isRemovable ? Icons.usb : Icons.storage,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(root.label, style: theme.textTheme.bodyLarge),
                  if (root.filesystem.isNotEmpty)
                    Text(
                      root.filesystem,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              _formatBytes(root.freeBytes),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(BigInt bytes) {
    if (bytes <= BigInt.zero) return '—';
    final mb = BigInt.from(1024) * BigInt.from(1024);
    final gb = mb * BigInt.from(1024);
    if (bytes < gb) {
      return '${(bytes / mb).toStringAsFixed(0)} MB free';
    }
    return '${(bytes / gb).toStringAsFixed(1)} GB free';
  }
}

/// T-008: the scrollable list body. Wraps a [ListView.builder] with a
/// scroll-end listener that fires [onLoadMore] when the user reaches the
/// bottom of the loaded entries, but only if [hasMore] is true.
class FsListBody extends StatefulWidget {
  final List<rust.FsEntry> entries;
  final bool hasMore;
  final bool loading;
  final void Function(rust.FsEntry entry) onTapEntry;
  final VoidCallback onLoadMore;

  const FsListBody({
    required this.entries,
    required this.hasMore,
    required this.loading,
    required this.onTapEntry,
    required this.onLoadMore,
    super.key,
  });

  @override
  State<FsListBody> createState() => _FsListBodyState();
}

class _FsListBodyState extends State<FsListBody> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!widget.hasMore || widget.loading) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // Trigger when within 200 px of the end.
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.entries.length;
    return ListView.builder(
      controller: _scrollController,
      itemCount: count + (widget.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= count) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final entry = widget.entries[index];
        return FsListRow(
          entry: entry,
          isLast: index == count - 1,
          onTap: () => widget.onTapEntry(entry),
        );
      },
    );
  }
}

/// T-008: root-mode list body. Each `FsRoot` becomes a row.
class FsRootsBody extends StatelessWidget {
  final List<rust.FsRoot> roots;
  final void Function(rust.FsRoot root) onTapRoot;

  const FsRootsBody({
    required this.roots,
    required this.onTapRoot,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: roots.length,
      itemBuilder: (context, index) {
        return FsListRow.rootRow(
          root: roots[index],
          isLast: index == roots.length - 1,
          onTap: () => onTapRoot(roots[index]),
        );
      },
    );
  }
}
