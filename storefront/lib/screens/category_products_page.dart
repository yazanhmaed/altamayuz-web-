import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/public_product_model.dart';
import '../utils/responsive.dart';
import '../widgets/cart_bar.dart';
import '../widgets/product_card.dart';
import '../widgets/ui_helpers.dart';

class CategoryProductsPage extends StatelessWidget {
  final String category;
  const CategoryProductsPage({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(category)),
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
              .where((p) => p.category == category)
              .toList();

          if (products.isEmpty) {
            return const Center(child: Text('لا توجد منتجات في هذا التصنيف بعد'));
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
