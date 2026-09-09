import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altamayuz_storefront/widgets/ui_helpers.dart';
import 'package:altamayuz_storefront/widgets/product_card.dart';
import 'package:altamayuz_storefront/widgets/category_card.dart';
import 'package:altamayuz_storefront/models/public_product_model.dart';

/// Guards the decode-size plumbing: StoreImage forwards cacheWidth/cacheHeight
/// to Image.network, and the small-image call sites actually pass a small
/// value (not the full ~1600px source).
void main() {
  testWidgets('StoreImage forwards cacheWidth/cacheHeight', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StoreImage(
            url: 'https://x/a.jpg', cacheWidth: 123, cacheHeight: 45),
      ),
    );
    final img = tester.widget<Image>(find.byType(Image));
    // cacheWidth/cacheHeight are baked into a ResizeImage provider.
    final provider = img.image as ResizeImage;
    expect(provider.width, 123);
    expect(provider.height, 45);
  });

  testWidgets('StoreImage without cache args uses the raw NetworkImage',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StoreImage(url: 'https://x/a.jpg')),
    );
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.image, isA<NetworkImage>());
  });

  testWidgets('ProductCard / CategoryCard decode small, not full-res',
      (tester) async {
    const product = PublicProductModel(
      id: 'p1',
      name: 'حذاء',
      price: 100,
      salePrice: null,
      isFeatured: false,
      category: 'أحذية',
      variants: [
        ProductVariant(
            color: 'أسود', imageUrl: 'https://x/v.jpg', sizes: {'42': 2}),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 160,
            height: 240,
            child: ProductCard(product: product),
          ),
        ),
      ),
    );

    final widths = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<ResizeImage>()
        .map((r) => r.width)
        .toList();
    // cover image (450) + up to 3 dots (48) — all well under 1600.
    expect(widths, isNotEmpty);
    expect(widths.every((w) => w != null && w <= 500), isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 140,
            child: CategoryCard(
                name: 'أحذية', count: 3, coverImage: 'https://x/c.jpg'),
          ),
        ),
      ),
    );
    final catImg = tester.widget<Image>(find.byType(Image));
    expect((catImg.image as ResizeImage).width, 500);
  });
}
