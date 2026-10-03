// Regression tests for the thumbnail lifecycle after an in-place list
// refresh (e.g. deleting an entry). The fetch must start on mount, not
// from visibility bookkeeping: an earlier revision triggered it from a
// `VisibilityDetector` callback whose static last-visibility map
// survives unmounts, so remounted rows with identical geometry never
// received the initial "visible" callback and stayed placeholders until
// the page was left and re-entered.
//
// The provider is overridden with a recording fake so no FRB / network
// is involved.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/network/fs/fs_thumbnail_provider.dart';
import 'package:localsend_app/widget/remote_thumbnail.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

class _RecordingThumbnailService extends FsThumbnailService {
  final calls = <String>[];

  @override
  FsThumbnailState init() => FsThumbnailState(cache: FsThumbnailCache());

  @override
  Future<Uint8List?> fetchThumbnail({
    required Device device,
    required String fullPath,
    int width = 128,
    int height = 128,
  }) async {
    calls.add(fullPath);
    return Uint8List.fromList([1, 2, 3]);
  }
}

Device _device() => Device.empty.copyWith(fingerprint: 'test-fp');

ProviderOverride _override(_RecordingThumbnailService service) {
  return ProviderOverride(provider: fsThumbnailProvider, createState: (ref) => service);
}

Widget _wrap(List<ProviderOverride> overrides, Widget child) {
  return RefenaScope(
    overrides: overrides,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

RemoteThumbnail _thumb(String path) {
  return RemoteThumbnail(
    device: _device(),
    fullPath: path,
    width: 40,
    height: 40,
    placeholder: const Icon(Icons.image),
  );
}

void main() {
  testWidgets('fetches on mount without any visibility callback', (tester) async {
    final service = _RecordingThumbnailService();
    await tester.pumpWidget(
      _wrap([_override(service)], _thumb('photos/a.jpg')),
    );
    await tester.pump();
    expect(service.calls, ['photos/a.jpg']);
  });

  testWidgets('refetches when remounted at the same place, as after a delete + refresh', (tester) async {
    final service = _RecordingThumbnailService();
    final overrides = [_override(service)];

    // First mount — the row is visible and the thumbnail loads.
    await tester.pumpWidget(_wrap(overrides, _thumb('photos/a.jpg')));
    await tester.pump();
    expect(service.calls, ['photos/a.jpg']);

    // In-place refresh: the list empties (entry deleted) so the row
    // unmounts, then the refreshed list remounts an identical row.
    await tester.pumpWidget(_wrap(overrides, const SizedBox.shrink()));
    await tester.pump();
    await tester.pumpWidget(_wrap(overrides, _thumb('photos/a.jpg')));
    await tester.pump();
    expect(service.calls, ['photos/a.jpg', 'photos/a.jpg']);
  });

  testWidgets('does not refetch while the same path stays mounted', (tester) async {
    final service = _RecordingThumbnailService();
    await tester.pumpWidget(
      _wrap([_override(service)], _thumb('photos/a.jpg')),
    );
    await tester.pump();
    await tester.pumpWidget(
      _wrap([_override(service)], _thumb('photos/a.jpg')),
    );
    await tester.pump();
    expect(service.calls, ['photos/a.jpg']);
  });

  testWidgets('refetches when the row is recycled to another path', (tester) async {
    final service = _RecordingThumbnailService();
    await tester.pumpWidget(
      _wrap([_override(service)], _thumb('photos/a.jpg')),
    );
    await tester.pump();
    await tester.pumpWidget(
      _wrap([_override(service)], _thumb('photos/b.jpg')),
    );
    await tester.pump();
    expect(service.calls, ['photos/a.jpg', 'photos/b.jpg']);
  });
}
