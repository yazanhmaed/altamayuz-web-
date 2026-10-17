import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/public_product_model.dart';
import '../theme/app_theme.dart';
import 'ui_helpers.dart';

class ProductCard extends StatelessWidget {
  final PublicProductModel product;
  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final isAvailable = product.isAvailable;
    return Card(
      clipBehavior: Clip.antiAlias,
      // Tap feedback: a transparent Material + InkWell layered on top of the
      // (opaque) card content, so the ripple actually paints above the image
      // instead of being hidden behind it. clipBehavior keeps it inside the
      // card's rounded corners.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Card image renders at ~150px; decode at ~3x for high-DPI
                    // phones instead of the stored 1600px.
                    StoreImage(url: product.coverImage, cacheWidth: 450),
                    if (!isAvailable)
                      Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        alignment: Alignment.center,
                        child: const Text('غير متوفر حاليًا',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    if (product.isOnSale)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: DiscountBadge(percent: product.discountPercent),
                      ),
                  ],
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Text(product.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              Divider(
                height: 1,
                // ignore: deprecated_member_use
                color: AppColors.border.withOpacity(0.5),
                indent: 30,
                endIndent: 30,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 12, 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: PriceDisplay(product: product),
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.go(
                  '/product/${product.id}',
                  extra: product,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
