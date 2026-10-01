import 'dart:async';

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
        title: Text(t.settingsTab.network.fsBookmarksTitle),
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
              t.settingsTab.network.fsBookmarksEmpty,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              t.settingsTab.network.fsBookmarksHint,
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
            title: Text(bookmark.alias ?? bookmark.path),
            subtitle: Text(
              bookmark.path,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              color: Theme.of(context).colorScheme.error,
              onPressed: () => _showDeleteConfirm(bookmark),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDeleteConfirm(FsBookmark bookmark) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settingsTab.network.fsBookmarkDelete),
        content: Text(t.settingsTab.network.fsBookmarkDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: () {
              unawaited(ref.notifier(fsBookmarkProvider).removeBookmark(bookmark.path));
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.general.delete),
          ),
        ],
      ),
    );
  }
}
