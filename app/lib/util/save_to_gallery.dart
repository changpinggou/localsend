import 'package:gal/gal.dart';
import 'package:localsend_app/util/native/platform_check.dart';

/// T-009: save an image or video already on disk into the platform
/// photo gallery.
///
/// Returns `true` on success, `false` otherwise. Failure modes:
///   * the platform has no gallery (desktop / web) → `false`;
///   * the user denied permission → `false`;
///   * the file is missing or unreadable → `false` (with a logged
///     reason — see [Gal.putImage] / [Gal.putVideo]).
///
/// On iOS / Android, the file is added to the user's camera roll
/// via the platform-native API. We don't surface a SwiftUI / Activity
/// picker — `gal` is the only file-format-handling dependency the
/// project already declared, and adding a custom intent would re-
/// duplicate that work.
Future<bool> saveFileToGallery(String localPath, {required bool isImage}) async {
  if (!checkPlatformWithGallery()) return false;
  try {
    final granted = await Gal.requestAccess(toAlbum: false);
    if (!granted) return false;
    if (isImage) {
      await Gal.putImage(localPath);
    } else {
      await Gal.putVideo(localPath);
    }
    return true;
  } catch (_) {
    // Includes `MissingPluginException` in environments where the
    // `gal` native side is not registered (e.g. flutter_test,
    // desktop without the plugin installed).
    return false;
  }
}
