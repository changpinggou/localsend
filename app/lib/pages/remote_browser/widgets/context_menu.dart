import 'package:flutter/material.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;

/// T-016: 文件/文件夹上下文菜单
/// 长按时弹出，提供重命名、移动、删除、分享、属性等操作
class FsContextMenu {
  final BuildContext context;

  FsContextMenu(this.context);

  /// 显示上下文菜单
  /// 返回用户选择的操作，null 表示取消
  static Future<FsContextAction?> show({
    required BuildContext context,
    required rust.FsEntry entry,
    bool isRoot = false,
  }) {
    return showModalBottomSheet<FsContextAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏 - 显示文件名
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    entry.isDir ? Icons.folder : _fileIcon(entry.name),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 操作列表
            if (!isRoot) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('重命名'),
                onTap: () => Navigator.pop(context, FsContextAction.rename),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('移动'),
                onTap: () => Navigator.pop(context, FsContextAction.move),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '删除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.pop(context, FsContextAction.delete),
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享'),
              onTap: () => Navigator.pop(context, FsContextAction.share),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('属性'),
              onTap: () => Navigator.pop(context, FsContextAction.properties),
            ),
            const SizedBox(height: 8),
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
}

/// 上下文菜单的操作类型
enum FsContextAction {
  rename,
  move,
  delete,
  share,
  properties,
}
