import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/fs_bookmark_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Settings page for managing filesystem bookmarks.
class FsBookmarksPage extends StatefulWidget {
  const FsBookmarksPage({super.key});

  @override
  State<FsBookmarksPage> createState() => _FsBookmarksPageState();
}

class _FsBookmarksPageState extends State<FsBookmarksPage> with Refena {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fsBookmarkProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settingsTab.network.fsBookmarksTitle ?? 'File Bookmarks'),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.bookmarks.isEmpty
              ? _buildEmptyState()
              : _buildBookmarkList(state),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.notifier(fsBookmarkProvider).addBookmark(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              t.settingsTab.network.fsBookmarksEmpty ?? 'No bookmarks',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              t.settingsTab.network.fsBookmarksHint ??
                  'Add folders you want to share with other devices',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookmarkList(FsBookmarkState state) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = state.bookmarks[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.folder),
            title: Text(bookmark.alias ?? 'Folder ${index + 1}'),
            subtitle: Text(
              'Added ${_formatDate(bookmark.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showEditDialog(bookmark),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  color: Theme.of(context).colorScheme.error,
                  onPressed: () => _showDeleteConfirm(bookmark),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditDialog(FsBookmark bookmark) {
    final controller = TextEditingController(text: bookmark.alias ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settingsTab.network.fsBookmarkEdit ?? 'Edit Bookmark'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: t.settingsTab.network.fsBookmarkAlias ?? 'Alias',
            hintText: 'My Documents',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .notifier(fsBookmarkProvider)
                  .updateAlias(bookmark.id, controller.text);
              Navigator.pop(context);
            },
            child: Text(t.general.save ?? 'Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(FsBookmark bookmark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settingsTab.network.fsBookmarkDelete ?? 'Delete Bookmark'),
        content: Text(
          t.settingsTab.network.fsBookmarkDeleteConfirm ??
              'Are you sure you want to delete this bookmark?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.notifier(fsBookmarkProvider).removeBookmark(bookmark.id);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.general.delete ?? 'Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
