import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/custom_bottom_sheet.dart';
import 'package:routerino/routerino.dart';

/// T-007: confirmation notice shown the first time the user enables the
/// LocalU `fs` capability. Mirrors [QuickSaveNotice] in style.
class EnableFsNotice extends StatelessWidget {
  const EnableFsNotice({super.key});

  static Future<void> open(BuildContext context) async {
    if (checkPlatformIsDesktop()) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(t.settingsTab.network.enableFsNoticeTitle),
          content: Text(t.settingsTab.network.enableFsNoticeBody),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(t.general.close),
            ),
          ],
        ),
      );
    } else {
      await context.pushBottomSheet(() => const EnableFsNotice());
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomBottomSheet(
      title: t.settingsTab.network.enableFsNoticeTitle,
      description: t.settingsTab.network.enableFsNoticeBody,
      child: Center(
        child: ElevatedButton(
          onPressed: () => context.popUntilRoot(),
          child: Text(t.general.close),
        ),
      ),
    );
  }
}
