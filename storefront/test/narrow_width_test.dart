import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altamayuz_storefront/models/cart_discount.dart';
import 'package:altamayuz_storefront/models/public_product_model.dart';
import 'package:altamayuz_storefront/widgets/cart_discount_banner.dart';
import 'package:altamayuz_storefront/widgets/product_card.dart';

/// Narrow-width (320px iPhone SE) hardening regression guards. Flutter throws
/// a FlutterError on RenderFlex overflow during a test, so these fail loudly
/// if a layout regresses at small widths.
///
/// Scope note: these cover widgets whose layout is robust regardless of the
/// glyph-metrics of the font in use (the test environment has no real font).
/// Full-screen widgets with fixed-text Rows (e.g. CartContent's header/footer)
/// are verified by inspection + on-device, not here, since the test font
/// inflates text width enough to trip false overflows on fine code.
void main() {
  const longName =
      'حذاء جلد طبيعي فاخر كلاسيكي بتصميم إيطالي أنيق للمناسبات الرسمية';

  PublicProductModel product({double? salePrice, int variants = 4}) {
    return PublicProductModel(
      id: 'p1',
      name: longName,
      price: 129,
      salePrice: salePrice,
      isFeatured: false,
      category: 'أحذية رسمية',
      variants: List.generate(
        variants,
        (i) => ProductVariant(
          color: 'لون طويل الاسم رقم $i',
          imageUrl: '',
          sizes: const {'42': 3},
        ),
      ),
    );
  }

  Widget host(Widget child, {double width = 136}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: 200, child: child),
        ),
      ),
    );
  }

  testWidgets('ProductCard: discounted, long name, many variants @136px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(ProductCard(product: product(salePrice: 89))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProductCard: full-price variant @136px', (tester) async {
    await tester.pumpWidget(host(ProductCard(product: product(salePrice: null))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('CartDiscountBanner: long mixed tier labels @320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CartDiscountBanner(
            debugTiers: [
              CartDiscountTier(minQuantity: 2, type: 'percentage', value: 12.5),
              CartDiscountTier(minQuantity: 6, type: 'fixed', value: 17.75),
              CartDiscountTier(minQuantity: 12, type: 'percentage', value: 25),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('قطعتان فأكثر'), findsOneWidget);
    expect(find.textContaining('6 قطع فأكثر'), findsOneWidget);
  });

  test('CartDiscountTier.label phrasing', () {
    expect(
      const CartDiscountTier(minQuantity: 2, type: 'percentage', value: 10)
          .label,
      'قطعتان فأكثر: خصم 10%',
    );
    expect(
      const CartDiscountTier(minQuantity: 5, type: 'fixed', value: 15).label,
      '5 قطع فأكثر: خصم 15 د.أ',
    );
  });
}
