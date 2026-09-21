// T-009: pure state-machine tests for [FsDownloadService] /
// [FsDownloadState]. The actual stream / disk-write path is
// exercised by integration tests that bring up the fs server.

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/network/fs/fs_download_provider.dart';

void main() {
  group('FsDownloadState.initial', () {
    test('starts idle with no path / size / error', () {
      final state = FsDownloadState.initial();
      expect(state.sessionId, isNull);
      expect(state.path, isNull);
      expect(state.filename, isNull);
      expect(state.transferred, 0);
      expect(state.total, 0);
      expect(state.status, FsDownloadStatus.idle);
      expect(state.cachedPath, isNull);
      expect(state.destinationPath, isNull);
      expect(state.error, isNull);
    });
  });

  group('FsDownloadStatus enum', () {
    test('has the expected five variants', () {
      expect(
        FsDownloadStatus.values,
        containsAll(<FsDownloadStatus>[
          FsDownloadStatus.idle,
          FsDownloadStatus.downloading,
          FsDownloadStatus.finished,
          FsDownloadStatus.failed,
          FsDownloadStatus.cancelled,
        ]),
      );
    });
  });
}
