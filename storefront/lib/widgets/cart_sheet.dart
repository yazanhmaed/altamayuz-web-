import 'package:flutter/material.dart';
import '../cart/cart_controller.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../screens/checkout_page.dart';

class CartSheet extends StatelessWidget {
  const CartSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: ResponsiveCenter(
            maxWidth: 700,
            child: ValueListenableBuilder<List<CartLine>>(
              valueListenable: cartController,
              builder: (context, cart, _) {
                if (cart.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_bag_outlined, size: 48, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text('سلتك فاضية', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        const Text('تصفح المنتجات وأضف اللي يعجبك', style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 40, height: 4, color: AppColors.border),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: cart.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, i) {
                          final line = cart[i];
                          return Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(line.variant.imageUrl, width: 56, height: 56, fit: BoxFit.cover),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(line.product.name, style: Theme.of(context).textTheme.titleMedium),
                                    Text('${line.variant.color} — مقاس ${line.size}', style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => cartController.updateQuantity(line.key, line.quantity - 1),
                              ),
                              Text('${line.quantity}'),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => cartController.updateQuantity(line.key, line.quantity + 1),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                      child: Row(
                        children: [
                          Text('${cartController.total.toStringAsFixed(0)} د.أ', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage()));
                            },
                            child: const Text('متابعة الطلب'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
