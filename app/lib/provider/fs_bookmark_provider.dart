import 'dart:typed_data';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../util/native/fs_bookmark_channel.dart';

/// Represents a saved bookmark with its bookmark data and optional alias.
class FsBookmark {
  final String id;
  final String? alias;
  final Uint8List bookmarkData;
  final DateTime createdAt;

  FsBookmark({
    required this.id,
    this.alias,
    required this.bookmarkData,
    required this.createdAt,
  });
}

/// State for the bookmark provider.
class FsBookmarkState {
  final List<FsBookmark> bookmarks;
  final bool loading;
  final String? error;

  const FsBookmarkState({
    required this.bookmarks,
    this.loading = false,
    this.error,
  });

  factory FsBookmarkState.initial() => FsBookmarkState(
        bookmarks: [],
        loading: false,
      );

  FsBookmarkState copyWith({
    List<FsBookmark>? bookmarks,
    bool? loading,
    String? error,
  }) {
    return FsBookmarkState(
      bookmarks: bookmarks ?? this.bookmarks,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

/// Provider for managing security-scoped bookmarks.
final fsBookmarkProvider = NotifierProvider<FsBookmarkService, FsBookmarkState>((ref) {
  return FsBookmarkService();
});

class FsBookmarkService extends Notifier<FsBookmarkState> {
  static const String _prefKey = 'fs_bookmarks';

  @override
  FsBookmarkState init() {
    // Load saved bookmarks on init
    _loadBookmarks();
    return FsBookmarkState.initial();
  }

  /// Loads bookmarks from shared preferences.
  Future<void> _loadBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarkJson = prefs.getStringList(_prefKey) ?? [];

      final bookmarks = <FsBookmark>[];
      for (final json in bookmarkJson) {
        // Simple JSON parsing (in production, use proper serialization)
        final parts = json.split('|');
        if (parts.length >= 3) {
          bookmarks.add(FsBookmark(
            id: parts[0],
            alias: parts[1].isEmpty ? null : parts[1],
            bookmarkData: Uint8List.fromList(parts[2].codeUnits),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(parts[3]) ?? 0,
            ),
          ));
        }
      }

      state = state.copyWith(bookmarks: bookmarks);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load bookmarks: $e');
    }
  }

  /// Saves bookmarks to shared preferences.
  Future<void> _saveBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarkJson = state.bookmarks.map((b) {
        return '${b.id}|${b.alias ?? ''}|${String.fromCharCodes(b.bookmarkData)}|${b.createdAt.millisecondsSinceEpoch}';
      }).toList();
      await prefs.setStringList(_prefKey, bookmarkJson);
    } catch (e) {
      state = state.copyWith(error: 'Failed to save bookmarks: $e');
    }
  }

  /// Adds a new bookmark by picking a folder.
  Future<void> addBookmark() async {
    state = state.copyWith(loading: true);

    try {
      final bookmarkData = await FsBookmarkChannel.pickFolder();
      if (bookmarkData == null) {
        // User cancelled
        state = state.copyWith(loading: false);
        return;
      }

      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final bookmark = FsBookmark(
        id: id,
        bookmarkData: bookmarkData,
        createdAt: DateTime.now(),
      );

      state = state.copyWith(
        bookmarks: [...state.bookmarks, bookmark],
        loading: false,
      );

      await _saveBookmarks();
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Failed to add bookmark: $e',
      );
    }
  }

  /// Removes a bookmark.
  Future<void> removeBookmark(String id) async {
    state = state.copyWith(
      bookmarks: state.bookmarks.where((b) => b.id != id).toList(),
    );
    await _saveBookmarks();
  }

  /// Resolves a bookmark to a path.
  Future<String?> resolveBookmark(FsBookmark bookmark) async {
    // Validate bookmark first
    final isValid = await FsBookmarkChannel.isBookmarkValid(bookmark.bookmarkData);
    if (!isValid) {
      return null;
    }

    return await FsBookmarkChannel.resolveBookmark(bookmark.bookmarkData);
  }

  /// Updates the alias of a bookmark.
  Future<void> updateAlias(String id, String? alias) async {
    final bookmarks = state.bookmarks.map((b) {
      if (b.id == id) {
        return FsBookmark(
          id: b.id,
          alias: alias,
          bookmarkData: b.bookmarkData,
          createdAt: b.createdAt,
        );
      }
      return b;
    }).toList();

    state = state.copyWith(bookmarks: bookmarks);
    await _saveBookmarks();
  }
}
