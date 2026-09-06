import 'package:flutter/material.dart';
import '../cart/cart_controller.dart';
import '../screens/checkout_page.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Persistent bottom bar shown whenever the cart has at least one item,
/// with the running count/total and a shortcut straight to checkout. Shared
/// across every product-browsing page (home grid, category pages).
class CartBar extends StatelessWidget {
  const CartBar({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CartLine>>(
      valueListenable: cartController,
      builder: (context, cart, _) {
        if (cart.isEmpty) return const SizedBox.shrink();
        return Container(
          // Scaffold.bottomSheet hands down an unbounded width; pin it to the
          // screen width so ResponsiveCenter/Row get bounded constraints.
          width: MediaQuery.sizeOf(context).width,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
          child: ResponsiveCenter(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${cartController.itemCount} قطعة', style: Theme.of(context).textTheme.bodySmall),
                      Text('${cartController.total.toStringAsFixed(0)} د.أ', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage())),
                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('إتمام الطلب')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
