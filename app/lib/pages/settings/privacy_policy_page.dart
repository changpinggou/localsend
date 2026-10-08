import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/settings/privacy_policy_content.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage();

  @override
  Widget build(BuildContext context) {
    final content = LocaleSettings.currentLocale.languageCode == 'zh' ? privacyPolicyZh : privacyPolicyEn;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.settingsTab.other.privacyPolicy),
      ),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        children: [
          const SizedBox(height: 20),
          MarkdownBody(data: content),
          const SizedBox(height: 50),
        ],
      ),
    );
  }
}
