import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:localsend_app/util/native/directories.dart';

/// T-009: copy a file already on disk to a destination the user picks.
///
/// Mobile (iOS / Android): uses [getSaveLocation] from `file_selector`
/// to let the user pick a folder + filename. The dialog returns the
/// final target path; we then `File(localPath).copy(destPath)`.
///
/// Desktop (macOS / Windows / Linux): skips the picker and copies
/// into the OS downloads directory, then returns that path so the
/// UI can show a snackbar with the saved location.
Future<String?> saveFileToDownloads({
  required String localPath,
  required String filename,
}) async {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    final downloads = await getDownloadsDirectory();
    if (downloads == null) return null;
    final dest = '$downloads${Platform.pathSeparator}$filename';
    await File(localPath).copy(dest);
    return dest;
  }

  // Mobile: ask the user where to save. `getSaveLocation` returns a
  // `FileSaveLocation?` whose `path` is the chosen destination.
  const XTypeGroup typeGroup = XTypeGroup(label: 'files');
  final destination = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: const [typeGroup],
  );
  if (destination == null) return null;
  await File(localPath).copy(destination.path);
  return destination.path;
}
