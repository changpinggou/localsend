import 'package:flutter/foundation.dart';
// [FOSS_REMOVE_START]
import 'package:localsend_app/model/state/purchase_state.dart';
import 'package:localsend_app/provider/purchase_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
// [FOSS_REMOVE_END]
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// T-028: whether the Pro paywall applies on this platform.
/// Windows / Linux / macOS are entirely free — only Android + iOS gate,
/// which keeps [checkPlatformSupportPayment] (macOS donations) untouched.
bool checkProGatePlatform() {
  return checkPlatform([TargetPlatform.android, TargetPlatform.iOS]);
}

// [FOSS_REMOVE_START]
/// T-028: whether LocalU Pro is unlocked.
///
/// This is the single seam between the UI and the purchase state — future
/// server-side verification only changes this provider. The FOSS build
/// replaces it with [isProNoopProvider] via the stripping script, so UI
/// files reference [isProProvider] unconditionally.
final isProProvider = ViewProvider<bool>((ref) {
  if (!checkProGatePlatform()) {
    return true; // desktop is free
  }
  final purchase = ref.watch(purchaseProvider);
  final settings = ref.watch(settingsProvider);
  return purchase.purchases.contains(PurchaseItem.pro) || settings.proCached;
});
// [FOSS_REMOVE_END]

/// FOSS version of [isProProvider]: everything is free.
final isProNoopProvider = ViewProvider<bool>((ref) => true);
