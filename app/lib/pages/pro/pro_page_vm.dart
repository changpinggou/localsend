import 'package:localsend_app/model/state/purchase_state.dart';
import 'package:localsend_app/provider/pro_gate_provider.dart';
// [FOSS_REMOVE_START]
import 'package:localsend_app/provider/purchase_provider.dart';
// [FOSS_REMOVE_END]
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:refena_flutter/refena_flutter.dart';

class ProPageVm {
  final bool platformSupportPayment;
  final String? price; // null = unavailable
  final bool purchased;
  final bool pending;
  final void Function() purchase;
  final void Function() restore;

  ProPageVm({
    required this.platformSupportPayment,
    required this.price,
    required this.purchased,
    required this.pending,
    required this.purchase,
    required this.restore,
  });
}

// [FOSS_REMOVE_START]
final proPageVmProvider = ViewProvider<ProPageVm>((ref) {
  final state = ref.watch(purchaseProvider);
  return ProPageVm(
    platformSupportPayment: checkPlatformSupportPayment(),
    price: state.prices[PurchaseItem.pro],
    purchased: ref.watch(isProProvider),
    pending: state.pending,
    purchase: () => ref.redux(purchaseProvider).dispatchAsync(PurchaseAction(PurchaseItem.pro)), // ignore: discarded_futures
    restore: () => ref.redux(purchaseProvider).dispatchAsync(PurchaseRestoreAction()), // ignore: discarded_futures
  );
});
// [FOSS_REMOVE_END]

/// This is a noop version of the original view model.
/// Used to compile the FOSS version of the app by removing the original provider above.
final proPageNoopVmProvider = ViewProvider<ProPageVm>((ref) {
  return ProPageVm(
    platformSupportPayment: false,
    price: null,
    purchased: false,
    pending: false,
    purchase: () {},
    restore: () {},
  );
});
