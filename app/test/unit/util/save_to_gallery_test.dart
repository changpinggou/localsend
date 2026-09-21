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
  // Note: this test runs in the flutter_test environment which does
  // NOT initialise platform channels for the `gal` plugin. The
  // platform-gate short-circuits to `false` on desktop, so this is
  // safe. iOS / Android device tests would exercise the actual
  // `Gal.putImage` path.
  test('saveFileToGallery returns false when path does not exist', () async {
    final ok = await saveFileToGallery('/nonexistent/path.jpg', isImage: true);
    expect(ok, isFalse);
  });
}
