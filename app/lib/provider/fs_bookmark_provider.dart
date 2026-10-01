import 'dart:async';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_app/util/native/fs_bookmark_channel.dart';
import 'package:localsend_isolates/rust/api/server.dart' as rust_server;
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'fs_bookmark_provider.mapper.dart';

final _logger = Logger('FsBookmark');

/// Represents a saved filesystem bookmark.
@MappableClass()
class FsBookmark with FsBookmarkMappable {
  final String path;
  final String? alias;
  final DateTime createdAt;

  const FsBookmark({
    required this.path,
    this.alias,
    required this.createdAt,
  });
}

@MappableClass()
class FsBookmarkState with FsBookmarkStateMappable {
  final List<FsBookmark> bookmarks;
  final bool loading;
  final String? error;

  const FsBookmarkState({
    required this.bookmarks,
    required this.loading,
    this.error,
  });

  factory FsBookmarkState.initial() => FsBookmarkState(
    bookmarks: [],
    loading: false,
  );
}

final fsBookmarkProvider = NotifierProvider<FsBookmarkService, FsBookmarkState>((ref) {
  return FsBookmarkService();
});

class FsBookmarkService extends Notifier<FsBookmarkState> {
  static const String _prefKey = 'fs_bookmark_paths';

  @override
  FsBookmarkState init() {
    unawaited(_loadBookmarks());
    return FsBookmarkState.initial();
  }

  /// Loads bookmarks from SharedPreferences and syncs to Rust.
  Future<void> _loadBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_prefKey) ?? [];

      final bookmarks = <FsBookmark>[];
      for (final path in paths) {
        // Sync to Rust additional roots
        rust_server.addFsRoot(path: path);

        bookmarks.add(
          FsBookmark(
            path: path,
            createdAt: DateTime.now(),
          ),
        );
      }

      state = state.copyWith(bookmarks: bookmarks);
      _logger.info('Loaded ${bookmarks.length} bookmarks');
    } catch (e, st) {
      _logger.warning('Failed to load bookmarks', e, st);
      state = state.copyWith(error: 'Failed to load bookmarks: $e');
    }
  }

  /// Saves bookmark paths to SharedPreferences.
  Future<void> _saveBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = state.bookmarks.map((b) => b.path).toList();
      await prefs.setStringList(_prefKey, paths);
      _logger.info('Saved ${paths.length} bookmark paths');
    } catch (e, st) {
      _logger.warning('Failed to save bookmarks', e, st);
    }
  }

  /// Adds a bookmark by picking a folder (macOS only).
  ///
  /// This opens NSOpenPanel on macOS to let the user select a folder.
  /// The selected path is added to Rust's additional roots and saved
  /// to SharedPreferences.
  Future<void> addBookmark() async {
    state = state.copyWith(loading: true);

    try {
      final path = await _pickFolder();
      if (path == null) {
        // User cancelled
        state = state.copyWith(loading: false);
        return;
      }

      // Add to Rust
      rust_server.addFsRoot(path: path);

      // Add to state
      final bookmark = FsBookmark(
        path: path,
        createdAt: DateTime.now(),
      );

      state = state.copyWith(
        bookmarks: [...state.bookmarks, bookmark],
        loading: false,
      );

      await _saveBookmarks();
      _logger.info('Added bookmark: $path');
    } catch (e, st) {
      _logger.warning('Failed to add bookmark', e, st);
      state = state.copyWith(
        loading: false,
        error: 'Failed to add bookmark: $e',
      );
    }
  }

  /// Removes a bookmark.
  Future<void> removeBookmark(String path) async {
    try {
      // Remove from Rust
      rust_server.removeFsRoot(path: path);

      // Remove from state
      state = state.copyWith(
        bookmarks: state.bookmarks.where((b) => b.path != path).toList(),
      );

      await _saveBookmarks();
      _logger.info('Removed bookmark: $path');
    } catch (e, st) {
      _logger.warning('Failed to remove bookmark', e, st);
      state = state.copyWith(error: 'Failed to remove bookmark: $e');
    }
  }

  /// Updates the alias of a bookmark.
  Future<void> updateAlias(String path, String? alias) async {
    final bookmarks = state.bookmarks.map((b) {
      if (b.path == path) {
        return FsBookmark(
          path: b.path,
          alias: alias,
          createdAt: b.createdAt,
        );
      }
      return b;
    }).toList();

    state = state.copyWith(bookmarks: bookmarks);
    await _saveBookmarks();
  }

  /// Platform-specific folder picker.
  ///
  /// On macOS, this opens NSOpenPanel via FsBookmarkChannel.
  /// On other platforms, returns null (not implemented).
  Future<String?> _pickFolder() async {
    return await FsBookmarkChannel.pickFolder();
  }
}
