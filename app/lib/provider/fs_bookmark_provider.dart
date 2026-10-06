import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;

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

  /// Base64-encoded macOS security-scoped bookmark data.
  ///
  /// With the App Sandbox enabled, the folder access granted by NSOpenPanel
  /// is session-only; this bookmark is what [FsBookmarkChannel.startAccess]
  /// resolves on startup to restore the access. Null for entries migrated
  /// from the legacy path-only storage — those cannot restore their access
  /// and need to be re-picked once.
  final String? bookmark;

  const FsBookmark({
    required this.path,
    this.alias,
    required this.createdAt,
    this.bookmark,
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
  /// v2 storage: full bookmark JSON (path, alias, createdAt, bookmark data).
  static const String _prefKeyV2 = 'fs_bookmarks_v2';

  /// Legacy storage (path strings only). Kept around for rollback
  /// compatibility; migrated to [_prefKeyV2] on load.
  static const String _prefKeyLegacy = 'fs_bookmark_paths';

  @override
  FsBookmarkState init() {
    unawaited(_loadBookmarks());
    return FsBookmarkState.initial();
  }

  /// Loads bookmarks from SharedPreferences, restores the security-scoped
  /// access (macOS sandbox) and syncs the paths to Rust.
  Future<void> _loadBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      var changed = false;
      var bookmarks = _deserialize(prefs.getString(_prefKeyV2));

      if (bookmarks == null) {
        // Migrate from the legacy path-only storage.
        final paths = prefs.getStringList(_prefKeyLegacy) ?? [];
        bookmarks = [
          for (final path in paths) FsBookmark(path: path, createdAt: DateTime.now()),
        ];
        changed = bookmarks.isNotEmpty;
      }

      final restored = <FsBookmark>[];
      for (final bookmark in bookmarks) {
        var path = bookmark.path;
        if (bookmark.bookmark != null) {
          final resolved = await FsBookmarkChannel.startAccess(bookmark.bookmark!);
          if (resolved != null) {
            // The security-scoped access is now active for this process.
            // If the folder moved, the grant follows the bookmark.
            if (resolved != path) {
              _logger.info('Bookmark path changed: $path -> $resolved');
              path = resolved;
              changed = true;
            }
          } else {
            _logger.warning(
              'Could not restore access for $path (bookmark stale? folder moved or deleted?)',
            );
          }
        } else {
          _logger.warning(
            'Bookmark $path has no security-scoped data (added before the '
            'sandbox fix); re-add it in the shared folders settings once',
          );
        }

        // Sync to Rust additional roots
        rust_server.addFsRoot(path: path);

        restored.add(
          path == bookmark.path
              ? bookmark
              : FsBookmark(
                  path: path,
                  alias: bookmark.alias,
                  createdAt: bookmark.createdAt,
                  bookmark: bookmark.bookmark,
                ),
        );
      }

      state = state.copyWith(bookmarks: restored);
      if (changed) {
        await _saveBookmarks();
      }
      _logger.info('Loaded ${restored.length} bookmarks');
    } catch (e, st) {
      _logger.warning('Failed to load bookmarks', e, st);
      state = state.copyWith(error: 'Failed to load bookmarks: $e');
    }
  }

  /// Saves bookmarks (including security-scoped bookmark data) to
  /// SharedPreferences.
  Future<void> _saveBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = state.bookmarks.map((b) => b.toJson()).toList();
      await prefs.setString(_prefKeyV2, jsonEncode(json));
      _logger.info('Saved ${json.length} bookmarks');
    } catch (e, st) {
      _logger.warning('Failed to save bookmarks', e, st);
    }
  }

  List<FsBookmark>? _deserialize(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final list = jsonDecode(raw) as List<Object?>;
      return [
        for (final item in list) FsBookmarkMapper.fromJson(item! as Map<String, dynamic>),
      ];
    } catch (e) {
      _logger.warning('Failed to decode stored bookmarks: $e');
      return null;
    }
  }

  /// Adds a bookmark by picking a folder (macOS only).
  ///
  /// This opens NSOpenPanel on macOS to let the user select a folder.
  /// The selected path is added to Rust's additional roots and saved
  /// to SharedPreferences together with the security-scoped bookmark.
  Future<void> addBookmark() async {
    state = state.copyWith(loading: true);

    try {
      final pick = await FsBookmarkChannel.pickFolder();
      if (pick == null) {
        // User cancelled
        state = state.copyWith(loading: false);
        return;
      }

      // Add to Rust
      rust_server.addFsRoot(path: pick.path);

      // Add to state
      final bookmark = FsBookmark(
        path: pick.path,
        createdAt: DateTime.now(),
        bookmark: pick.bookmark,
      );

      state = state.copyWith(
        bookmarks: [...state.bookmarks, bookmark],
        loading: false,
      );

      await _saveBookmarks();
      _logger.info('Added bookmark: ${pick.path}');
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
          bookmark: b.bookmark,
        );
      }
      return b;
    }).toList();

    state = state.copyWith(bookmarks: bookmarks);
    await _saveBookmarks();
  }
}
