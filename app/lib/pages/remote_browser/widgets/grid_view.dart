import 'package:flutter/material.dart';
import 'package:localsend_app/widget/remote_thumbnail.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;

/// T-008: grid-mode cell. P5: image entries render a [RemoteThumbnail]
/// fetched from `/api/localsend/v2/fs/thumbnail?path=...&w=128&h=128`;
/// folders and non-image files keep type icons.
class FsGridCell extends StatelessWidget {
  final rust.FsEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Present when the cell should render a real thumbnail for image
  /// entries. When null, the cell falls back to type icons (e.g. at the
  /// roots level or when thumbnails are disabled).
  final Device? device;

  /// The current directory path (relative to the mount root). Combined
  /// with [entry.name] to form the full remote path for the thumbnail
  /// request. Ignored when [device] is null.
  final String currentPath;

  const FsGridCell({
    required this.entry,
    required this.onTap,
    this.onLongPress,
    this.device,
    this.currentPath = '',
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
                child: _buildThumbnailOrIcon(context, theme),
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

  /// Chooses between a real thumbnail and a type icon based on the
  /// entry's MIME type and whether we have a [device] to talk to.
  Widget _buildThumbnailOrIcon(BuildContext context, ThemeData theme) {
    final bool isImage = !entry.isDir && entry.mime != null && entry.mime!.startsWith('image/');

    if (isImage && device != null) {
      final fullPath = currentPath.isEmpty
          ? entry.name
          : '$currentPath/${entry.name}';
      return Center(
        child: RemoteThumbnail(
          device: device!,
          fullPath: fullPath,
          width: 96,
          height: 96,
          placeholder: Icon(
            _fileIcon(entry.name),
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Icon(
      entry.isDir ? Icons.folder : _fileIcon(entry.name),
      size: 48,
      color: entry.isDir ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
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

  /// When set, image entries render real thumbnails via [RemoteThumbnail].
  final Device? device;

  /// Current directory path (relative to mount root) used to build full
  /// remote paths for thumbnail requests.
  final String currentPath;

  const FsGridBody({
    required this.entries,
    required this.onTapEntry,
    this.onLongPressEntry,
    this.device,
    this.currentPath = '',
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
        final entry = entries[index];
        return FsGridCell(
          entry: entry,
          onTap: () => onTapEntry(entry),
          onLongPress: onLongPressEntry != null
              ? () => onLongPressEntry!(entry)
              : null,
          device: device,
          currentPath: currentPath,
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
