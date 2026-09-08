import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/public_product_model.dart';
import '../utils/responsive.dart';
import '../widgets/cart_bar.dart';
import '../widgets/product_card.dart';
import '../widgets/ui_helpers.dart';

class CategoryProductsPage extends StatelessWidget {
  /// When set, only products in this category are shown.
  final String? category;

  /// When true, only products currently on sale are shown.
  final bool onlyOnSale;

  /// Overrides the app bar title (defaults to [category] or a sale label).
  final String? titleOverride;

  const CategoryProductsPage({
    super.key,
    this.category,
    this.onlyOnSale = false,
    this.titleOverride,
  }) : assert(category != null || onlyOnSale, 'need a category or a filter');

  String get _title => titleOverride ?? category ?? 'عروض خاصة';

  bool _matches(PublicProductModel p) {
    if (category != null && p.category != category) return false;
    if (onlyOnSale && !p.isOnSale) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return ResponsiveCenter(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.68,
                ),
                itemCount: 6,
                itemBuilder: (_, __) => const ProductCardSkeleton(),
              ),
            );
          }

          final products = snapshot.data!.docs
              .map((d) => PublicProductModel.fromProductDoc(
                    d.id,
                    d.data() as Map<String, dynamic>,
                  ))
              .whereType<PublicProductModel>()
              .where(_matches)
              .toList();

          if (products.isEmpty) {
            return Center(
              child: Text(onlyOnSale
                  ? 'لا توجد عروض متاحة حاليًا'
                  : 'لا توجد منتجات في هذا التصنيف بعد'),
            );
          }

          return ResponsiveCenter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = Responsive.gridColumns(constraints.maxWidth);
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.68,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, i) => ProductCard(product: products[i]),
                );
              },
            ),
          );
        },
      ),
      bottomSheet: const CartBar(),
    );
  }
}
