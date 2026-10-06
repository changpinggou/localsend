import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/pro/pro_page_vm.dart';
// [FOSS_REMOVE_START]
import 'package:localsend_app/provider/purchase_provider.dart';
// [FOSS_REMOVE_END]
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// T-028: unlock page for LocalU Pro (one-time buyout).
///
/// Mirrors the donation page pipeline but with a single product card and
/// no external payment links — those are a store-review rejection.
class ProPage extends StatelessWidget {
  const ProPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: (ref) => proPageVmProvider,
      // [FOSS_REMOVE_START]
      init: (context) => context.redux(purchaseProvider).dispatchAsync(FetchPricesOnceAction()), // ignore: discarded_futures
      // [FOSS_REMOVE_END]
      builder: (context, vm) {
        return Scaffold(
          appBar: AppBar(
            title: Text(t.proPage.title),
          ),
          body: Stack(
            children: [
              ResponsiveListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 50),
                  const Center(
                    child: Icon(Icons.workspace_premium, size: 80),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      t.proPage.subtitle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _FeatureRow(
                    icon: Icons.touch_app,
                    title: t.proPage.features.oneTapTitle,
                    desc: t.proPage.features.oneTapDesc,
                  ),
                  const SizedBox(height: 20),
                  _FeatureRow(
                    icon: Icons.sync,
                    title: t.proPage.features.incrementalTitle,
                    desc: t.proPage.features.incrementalDesc,
                  ),
                  const SizedBox(height: 20),
                  _FeatureRow(
                    icon: Icons.cloud_done,
                    title: t.proPage.features.icloudTitle,
                    desc: t.proPage.features.icloudDesc,
                  ),
                  const SizedBox(height: 50),
                  if (vm.purchased)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Center(
                        child: Text(
                          t.proPage.thanks,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    ),
                  if (vm.platformSupportPayment)
                    Center(
                      child: FilledButton.icon(
                        onPressed: vm.purchased || vm.price == null ? null : vm.purchase,
                        icon: const Icon(Icons.lock_open),
                        label: Text(
                          vm.purchased
                              ? t.proPage.purchased
                              : vm.price != null
                              ? t.proPage.buy(price: vm.price!)
                              : t.proPage.priceUnavailable,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Text(
                        t.proPage.unavailable,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (vm.platformSupportPayment)
                    Center(
                      child: TextButton.icon(
                        onPressed: vm.restore,
                        icon: const Icon(Icons.restore),
                        label: Text(t.proPage.restore),
                      ),
                    ),
                ],
              ),
              if (vm.pending)
                Container(
                  color: Colors.black.withValues(alpha: 0.1),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// T-028: one highlighted selling point on the Pro page.
class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _FeatureRow({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 22,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
