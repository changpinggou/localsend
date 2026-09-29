import 'package:flutter/material.dart';

/// T-016: 多选模式的底部操作栏
class FsMultiSelectBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const FsMultiSelectBar({
    required this.selectedCount,
    required this.onMove,
    required this.onDelete,
    required this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 选中数量
            Text(
              '已选择 $selectedCount 项',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            // 移动按钮
            TextButton.icon(
              onPressed: onMove,
              icon: const Icon(Icons.drive_file_move_outline),
              label: const Text('移动'),
            ),
            const SizedBox(width: 8),
            // 删除按钮
            TextButton.icon(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              label: Text(
                '删除',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            const SizedBox(width: 8),
            // 取消按钮
            TextButton(
              onPressed: onCancel,
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}
