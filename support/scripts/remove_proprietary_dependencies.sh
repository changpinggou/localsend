#!/bin/sh

# This script removes proprietary dependencies from the project.

cd app

REGEX_A="s/\/\/ \[FOSS_REMOVE_START\]/\/*/"
REGEX_B="s/\/\/ \[FOSS_REMOVE_END\]/\*\//"

# Remove lines from pubspec.yaml
sed -i '/# \[FOSS_REMOVE\]/d' pubspec.yaml

# Comment out parts in Dart files
sed -i "$REGEX_A" lib/config/init.dart
sed -i "$REGEX_B" lib/config/init.dart

sed -i "$REGEX_A" lib/pages/donation/donation_page.dart
sed -i "$REGEX_B" lib/pages/donation/donation_page.dart

sed -i "$REGEX_A" lib/pages/donation/donation_page_vm.dart
sed -i "$REGEX_B" lib/pages/donation/donation_page_vm.dart

sed -i "$REGEX_A" lib/pages/pro/pro_page.dart
sed -i "$REGEX_B" lib/pages/pro/pro_page.dart

sed -i "$REGEX_A" lib/pages/pro/pro_page_vm.dart
sed -i "$REGEX_B" lib/pages/pro/pro_page_vm.dart

sed -i "$REGEX_A" lib/provider/pro_gate_provider.dart
sed -i "$REGEX_B" lib/provider/pro_gate_provider.dart

# Remove files completely
rm lib/provider/purchase_provider.dart

# Refer to donationPageNoopVmProvider instead of donationPageVmProvider
sed -i 's/donationPageVmProvider/donationPageNoopVmProvider/g' lib/pages/donation/donation_page.dart

# Refer to proPageNoopVmProvider instead of proPageVmProvider
sed -i 's/proPageVmProvider/proPageNoopVmProvider/g' lib/pages/pro/pro_page.dart

# Refer to isProNoopProvider (always true) instead of isProProvider.
# Only the consumers are rewritten — pro_gate_provider.dart itself already
# defines isProNoopProvider next to the removed block.
sed -i 's/isProProvider/isProNoopProvider/g' lib/pages/remote_browser_page.dart lib/pages/tabs/settings_tab.dart

cd ..
echo "Proprietary dependencies removed."
