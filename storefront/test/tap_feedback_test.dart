import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altamayuz_storefront/models/public_product_model.dart';
import 'package:altamayuz_storefront/widgets/category_card.dart';
import 'package:altamayuz_storefront/widgets/product_card.dart';

/// Guards that the card tap wrappers are Material InkWells (ripple feedback),
/// not bare GestureDetectors, and that the ink layer sits on its own
/// transparent Material so the splash paints above the opaque card content.
void main() {
  PublicProductModel product() => const PublicProductModel(
        id: 'p1',
        name: 'حذاء',
        price: 100,
        salePrice: null,
        isFeatured: false,
        category: 'أحذية',
        variants: [
          ProductVariant(color: 'أسود', imageUrl: '', sizes: {'42': 2}),
        ],
      );

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 160, height: 220, child: child),
          ),
        ),
      );

  testWidgets('ProductCard uses an InkWell with an onTap', (tester) async {
    await tester.pumpWidget(host(ProductCard(product: product())));

    final inkWell = tester.widget<InkWell>(
      find.descendant(
        of: find.byType(ProductCard),
        matching: find.byType(InkWell),
      ),
    );
    expect(inkWell.onTap, isNotNull);

    // Press and hold: the ink splash animates in without throwing.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ProductCard)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('CategoryCard uses an InkWell with an onTap', (tester) async {
    await tester.pumpWidget(
      host(const CategoryCard(name: 'أحذية', count: 3, coverImage: '')),
    );

    final inkWell = tester.widget<InkWell>(
      find.descendant(
        of: find.byType(CategoryCard),
        matching: find.byType(InkWell),
      ),
    );
    expect(inkWell.onTap, isNotNull);
  });
}
