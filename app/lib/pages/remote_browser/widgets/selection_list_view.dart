import 'package:flutter/material.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;

/// T-016: 多选模式的列表项，带复选框
class FsSelectableListRow extends StatelessWidget {
  final rust.FsEntry entry;
  final bool isLast;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FsSelectableListRow({
    required this.entry,
    required this.isLast,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: () {
        debugPrint('[T-016 DEBUG] FsSelectableListRow onLongPress triggered for: ${entry.name}');
        onLongPress();
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.1) : null,
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
            // 复选框
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onTap(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 12),
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : null,
                ),
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
}

/// T-016: 多选模式的列表主体
class FsSelectableListBody extends StatefulWidget {
  final List<rust.FsEntry> entries;
  final Set<String> selectedPaths;
  final String currentPath;
  final bool hasMore;
  final bool loading;
  final void Function(rust.FsEntry entry) onTapEntry;
  final void Function(rust.FsEntry entry) onLongPressEntry;
  final VoidCallback onLoadMore;

  const FsSelectableListBody({
    required this.entries,
    required this.selectedPaths,
    required this.currentPath,
    required this.hasMore,
    required this.loading,
    required this.onTapEntry,
    required this.onLongPressEntry,
    required this.onLoadMore,
    super.key,
  });

  @override
  State<FsSelectableListBody> createState() => _FsSelectableListBodyState();
}

class _FsSelectableListBodyState extends State<FsSelectableListBody> {
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
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      widget.onLoadMore();
    }
  }

  String _fullPath(rust.FsEntry entry) {
    return widget.currentPath.isEmpty ? entry.name : '${widget.currentPath}/${entry.name}';
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
        final fullPath = _fullPath(entry);
        final isSelected = widget.selectedPaths.contains(fullPath);
        return FsSelectableListRow(
          entry: entry,
          isLast: index == count - 1,
          isSelected: isSelected,
          onTap: () => widget.onTapEntry(entry),
          onLongPress: () => widget.onLongPressEntry(entry),
        );
      },
    );
  }
}
