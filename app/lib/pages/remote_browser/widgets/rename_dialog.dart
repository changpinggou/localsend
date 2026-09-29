import 'package:flutter/material.dart';

/// T-016: 重命名对话框
class FsRenameDialog extends StatefulWidget {
  final String currentName;
  final bool isDirectory;

  const FsRenameDialog({
    required this.currentName,
    required this.isDirectory,
    super.key,
  });

  @override
  State<FsRenameDialog> createState() => _FsRenameDialogState();
}

class _FsRenameDialogState extends State<FsRenameDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isDirectory ? '重命名文件夹' : '重命名文件'),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '输入新名称',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) => _submit(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => _submit(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }

  void _submit(String newName) {
    final trimmed = newName.trim();
    if (trimmed.isNotEmpty && trimmed != widget.currentName) {
      Navigator.of(context).pop(trimmed);
    }
  }
}

/// 显示重命名对话框
Future<String?> showRenameDialog({
  required BuildContext context,
  required String currentName,
  required bool isDirectory,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => FsRenameDialog(
      currentName: currentName,
      isDirectory: isDirectory,
    ),
  );
}
