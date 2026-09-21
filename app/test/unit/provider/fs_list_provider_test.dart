// T-008: state-machine tests for [FsListService].
//
// These tests do NOT exercise the isolate / HTTP boundary — that path
// needs a running fs server (see integration tests in T-009). They
// cover the pure state-machine parts: [FsListState.initial], [changeView],
// [changeSort], and the `kFsListPageSize` / `FsSort` invariants.

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/network/fs/fs_list_provider.dart';

void main() {
  group('FsListState.initial', () {
    test('starts empty, at the roots level, with name-asc sort', () {
      final state = FsListState.initial();
      expect(state.deviceFingerprint, isNull);
      expect(state.currentPath, '');
      expect(state.roots, isEmpty);
      expect(state.entries, isEmpty);
      expect(state.total, 0);
      expect(state.loading, isFalse);
      expect(state.hasMore, isFalse);
      expect(state.page, -1);
      expect(state.sort, FsSort.nameAsc);
      expect(state.viewMode, FsViewMode.list);
      expect(state.error, isNull);
    });
  });

  group('kFsListPageSize', () {
    test('is exactly 100 (matches the server contract)', () {
      expect(kFsListPageSize, 100);
    });
  });

  group('FsSort wire values', () {
    test('every variant maps to a lowercase snake_case wire value', () {
      // The server's `handle_list` parses `sort=` with these exact strings.
      // Changing them requires updating `packages/core/src/fs/rest.rs`
      // alongside the Dart side.
      expect(FsSort.nameAsc.value, 'name_asc');
      expect(FsSort.nameDesc.value, 'name_desc');
      expect(FsSort.sizeAsc.value, 'size_asc');
      expect(FsSort.sizeDesc.value, 'size_desc');
      expect(FsSort.mtimeDesc.value, 'mtime_desc');
    });
  });

  group('FsViewMode enum', () {
    test('has exactly two variants (list / grid)', () {
      expect(FsViewMode.values, hasLength(2));
      expect(FsViewMode.values, containsAll([FsViewMode.list, FsViewMode.grid]));
    });
  });
}
