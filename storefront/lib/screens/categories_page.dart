import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/public_product_model.dart';
import '../utils/responsive.dart';
import '../widgets/cart_bar.dart';
import '../widgets/category_card.dart';

/// Grid of category cards, each showing the first product's image as its cover
/// and opening the matching category page. Reached from the home footer; the
/// home screen shows the same cards capped to a few rows.
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأصناف')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = snapshot.data!.docs
              .map((d) => PublicProductModel.fromProductDoc(
                    d.id,
                    d.data() as Map<String, dynamic>,
                  ))
              .whereType<PublicProductModel>()
              .toList();

          // One entry per category: product count + the first product seen in
          // that category (its image becomes the card cover).
          final counts = <String, int>{};
          final firstProduct = <String, PublicProductModel>{};
          for (final p in products) {
            counts[p.category] = (counts[p.category] ?? 0) + 1;
            firstProduct.putIfAbsent(p.category, () => p);
          }
          final categories = counts.keys.toList()..sort();

          if (categories.isEmpty) {
            return const Center(child: Text('لا توجد أصناف متاحة حاليًا'));
          }

          return ResponsiveCenter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = Responsive.gridColumns(constraints.maxWidth);
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.3,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, i) => CategoryCard(
                    name: categories[i],
                    count: counts[categories[i]]!,
                    coverImage: firstProduct[categories[i]]!.coverImage,
                  ),
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
