import 'package:flutter/material.dart';
import '../models/public_product_model.dart';
import '../screens/product_detail_page.dart';
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
                    StoreImage(url: product.coverImage),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Text(product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    // In a ~2-column grid cell at 320px the content box is only
                    // ~110px wide; a discounted PriceDisplay (two figures) plus
                    // the dots would otherwise RenderFlex-overflow. Let the price
                    // take the free space and scale down only if it must.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: PriceDisplay(product: product),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...product.variants.take(3).map(
                          (v) => Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.border,
                                border: Border.all(color: AppColors.border),
                              ),
                              child:
                                  ClipOval(child: StoreImage(url: v.imageUrl)),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetailPage(product: product),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
