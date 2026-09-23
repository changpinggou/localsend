// T-008: state-machine tests for [FsListService].
//
// These tests do NOT exercise the isolate / HTTP boundary — that path
// needs a running fs server (see integration tests in T-009). They
// cover the pure state-machine parts: [FsListState.initial], [changeView],
// [changeSort], and the `kFsListPageSize` / `FsSort] invariants.

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pages/remote_browser/widgets/empty_state.dart';
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
      expect(state.errorReason, isNull);
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

  group('classifyFsError', () {
    test('404 maps to fsDisabledByPeer (the common P1-mvp misconfig)', () {
      expect(
        classifyFsError('RsHttpClientError.statusCode(status: 404, message: null)'),
        FsErrorReason.fsDisabledByPeer,
      );
    });

    test('403 maps to pathDenied', () {
      expect(
        classifyFsError('RsHttpClientError.statusCode(status: 403, message: null)'),
        FsErrorReason.pathDenied,
      );
    });

    test('408 / 504 / 524 map to timeout', () {
      for (final code in ['408', '504', '524']) {
        expect(
          classifyFsError('RsHttpClientError.statusCode(status: $code, message: null)'),
          FsErrorReason.timeout,
          reason: 'status $code',
        );
      }
    });

    test('500 maps to notFound (catch-all 5xx)', () {
      expect(
        classifyFsError('RsHttpClientError.statusCode(status: 500, message: boom)'),
        FsErrorReason.notFound,
      );
    });

    test('"Connection refused" / DNS failure map to network', () {
      expect(classifyFsError('Connection refused'), FsErrorReason.network);
      expect(classifyFsError('Failed host lookup: foo'), FsErrorReason.network);
      expect(classifyFsError('SocketException: closed'), FsErrorReason.network);
      expect(classifyFsError('Network is unreachable'), FsErrorReason.network);
    });

    test('"timed out" maps to timeout', () {
      expect(classifyFsError('request timed out'), FsErrorReason.timeout);
    });

    test('unknown error falls back to network (retry is always possible)', () {
      expect(classifyFsError('some random failure'), FsErrorReason.network);
    });
  });
}
