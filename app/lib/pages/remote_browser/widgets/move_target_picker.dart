import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/provider/network/fs/fs_list_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;
import 'package:refena_flutter/refena_flutter.dart';

/// T-016: 移动目标选择器
/// 允许用户浏览目录并选择目标位置
class FsMoveTargetPicker extends StatefulWidget {
  final Device device;
  final List<String> excludedPaths; // 排除要移动的文件/文件夹本身

  const FsMoveTargetPicker({
    required this.device,
    required this.excludedPaths,
    super.key,
  });

  @override
  State<FsMoveTargetPicker> createState() => _FsMoveTargetPickerState();
}

class _FsMoveTargetPickerState extends State<FsMoveTargetPicker> with Refena {
  String _currentPath = '';
  List<rust.FsEntry> _entries = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadEntries(''));
  }

  Future<void> _loadEntries(String path) async {
    setState(() {
      _loading = true;
      _currentPath = path;
    });

    try {
      final state = ref.read(fsListProvider);
      if (path.isEmpty) {
        // 根目录 - 显示挂载点
        final roots = state.roots;
        setState(() {
          _entries = roots
              .map(
                (r) => rust.FsEntry(
                  name: r.label,
                  isDir: true,
                  size: BigInt.zero,
                  mtime: 0,
                  mime: null,
                ),
              )
              .toList();
        });
      } else {
        // 加载目录内容
        final entries = state.entries;
        setState(() {
          _entries = entries.where((e) {
            // 过滤掉要移动的项
            final fullPath = path.isEmpty ? e.name : '$path/${e.name}';
            return !widget.excludedPaths.contains(fullPath);
          }).toList();
        });
      }
    } catch (e) {
      // 错误处理
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _navigateInto(rust.FsEntry entry) {
    if (!entry.isDir) return;
    final newPath = _currentPath.isEmpty ? entry.name : '$_currentPath/${entry.name}';
    unawaited(_loadEntries(newPath));
  }

  void _navigateUp() {
    if (_currentPath.isEmpty) return;
    final lastSlash = _currentPath.lastIndexOf('/');
    if (lastSlash == -1) {
      unawaited(_loadEntries(''));
    } else {
      unawaited(_loadEntries(_currentPath.substring(0, lastSlash)));
    }
  }

  void _selectCurrentDirectory() {
    Navigator.of(context).pop(_currentPath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('移动到'),
        leading: _currentPath.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateUp,
              ),
        actions: [
          TextButton(
            onPressed: _selectCurrentDirectory,
            child: Text(
              '选择此目录',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 面包屑导航
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentPath.isEmpty ? '根目录' : _currentPath,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 目录列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                ? Center(
                    child: Text(
                      '此目录为空',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      if (!entry.isDir) return const SizedBox.shrink();
                      return ListTile(
                        leading: Icon(
                          Icons.folder,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(entry.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _navigateInto(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 显示移动目标选择器
Future<String?> showMoveTargetPicker({
  required BuildContext context,
  required Device device,
  required List<String> excludedPaths,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (context) => FsMoveTargetPicker(
        device: device,
        excludedPaths: excludedPaths,
      ),
    ),
  );
}
