// T-009: tests for [saveFileToGallery].
//
// The real `gal` plugin requires platform channels, which are not
// available in `flutter_test`. We exercise the parts we can:
//   * the function returns `false` on platforms that have no
//     gallery (the production app gates this on
//     `checkPlatformWithGallery()`);
//   * the function gracefully reports `false` when the source
//     file does not exist.

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/save_to_gallery.dart';

void main() {
  // `saveFileToGallery` calls into `checkPlatformWithGallery()`, which
  // reaches for `defaultTargetPlatform` from the WidgetsBinding — that
  // binding is not initialised by default in a pure `flutter_test`
  // environment, so we ensure it here.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveFileToGallery returns false when path does not exist', () async {
    final ok = await saveFileToGallery('/nonexistent/path.jpg', isImage: true);
    expect(ok, isFalse);
  });
}
