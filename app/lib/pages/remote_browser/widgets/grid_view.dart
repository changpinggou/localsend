import 'package:flutter/material.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;

/// T-008: grid-mode cell. P5 will replace the [Icons.*] placeholder with
/// a real `Thumbnail` widget that lazily fetches
/// `/api/localsend/v2/fs/thumbnail?path=...&w=128&h=128`; for P1 we use a
/// type icon so the layout is ready and the upgrade path is local.
class FsGridCell extends StatelessWidget {
  final rust.FsEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const FsGridCell({
    required this.entry,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  static Widget rootCell({
    required rust.FsRoot root,
    required VoidCallback onTap,
  }) {
    return _RootCell(root: root, onTap: onTap);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress != null
          ? () {
              debugPrint('[T-016 DEBUG] FsGridCell onLongPress triggered for: ${entry.name}');
              onLongPress!();
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  entry.isDir ? Icons.folder : _fileIcon(entry.name),
                  size: 48,
                  color: entry.isDir ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
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
    return Icons.insert_drive_file_outlined;
  }
}

class _RootCell extends StatelessWidget {
  final rust.FsRoot root;
  final VoidCallback onTap;

  const _RootCell({required this.root, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  root.isRemovable ? Icons.usb : Icons.storage,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              root.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid body wrapping a [GridView.builder] with cross-axis count of 3.
/// Long-press is left to the parent.
class FsGridBody extends StatelessWidget {
  final List<rust.FsEntry> entries;
  final void Function(rust.FsEntry entry) onTapEntry;
  final void Function(rust.FsEntry entry)? onLongPressEntry;

  const FsGridBody({
    required this.entries,
    required this.onTapEntry,
    this.onLongPressEntry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.75,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return FsGridCell(
          entry: entries[index],
          onTap: () => onTapEntry(entries[index]),
          onLongPress: onLongPressEntry != null
              ? () => onLongPressEntry!(entries[index])
              : null,
        );
      },
    );
  }
}

class FsRootsGridBody extends StatelessWidget {
  final List<rust.FsRoot> roots;
  final void Function(rust.FsRoot root) onTapRoot;

  const FsRootsGridBody({
    required this.roots,
    required this.onTapRoot,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.75,
      ),
      itemCount: roots.length,
      itemBuilder: (context, index) {
        return FsGridCell.rootCell(root: roots[index], onTap: () => onTapRoot(roots[index]));
      },
    );
  }
}
