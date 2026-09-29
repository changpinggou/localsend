import 'package:flutter/material.dart';

/// T-016: 删除确认对话框
class FsDeleteConfirmDialog extends StatefulWidget {
  final int itemCount;

  const FsDeleteConfirmDialog({
    required this.itemCount,
    super.key,
  });

  @override
  State<FsDeleteConfirmDialog> createState() => _FsDeleteConfirmDialogState();
}

class _FsDeleteConfirmDialogState extends State<FsDeleteConfirmDialog> {
  bool _useRecycleBin = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('删除 ${widget.itemCount} 项?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '此操作将永久删除所选项目。',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          // 回收站选项
          CheckboxListTile(
            title: const Text('移入回收站'),
            subtitle: Text(
              '取消勾选将永久删除，无法恢复',
              style: theme.textTheme.bodySmall,
            ),
            value: _useRecycleBin,
            onChanged: (value) {
              setState(() {
                _useRecycleBin = value ?? true;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_useRecycleBin),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          child: const Text('删除'),
        ),
      ],
    );
  }
}

/// 显示删除确认对话框
/// 返回是否使用回收站（true=使用回收站，false=永久删除，null=取消）
Future<bool?> showDeleteConfirmDialog({
  required BuildContext context,
  required int itemCount,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => FsDeleteConfirmDialog(itemCount: itemCount),
  );
}
