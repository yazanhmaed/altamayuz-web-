// Same cases as functions/test/pricing.test.ts and
// storefront/test/promotion_pricing_test.dart.
import 'package:altamayuz_admin/utils/promotion_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 11, 11, 12);
DateTime hours(int h) => now.add(Duration(hours: h));

Promotion promo({
  String id = 'p1',
  double? amountOff = 5,
  double? percent,
  List<String> productIds = const ['shoe'],
  DateTime? startAt,
  DateTime? endAt,
  bool isActive = true,
}) =>
    Promotion(
      id: id,
      name: 'Promo',
      amountOff: amountOff,
      percent: percent,
      productIds: productIds,
      startAt: startAt ?? hours(-1),
      endAt: endAt ?? hours(1),
      isActive: isActive,
    );

EffectivePrice price(List<Promotion> promos,
        {double base = 50, double? sale}) =>
    effectivePrice(
      productId: 'shoe',
      price: base,
      salePrice: sale,
      promotions: promos,
      now: now,
    );

void main() {
  test('no promo', () {
    final r = price([]);
    expect(r.price, 50);
    expect(r.source, 'none');
    expect(r.discountPercent, 0);
    expect(r.savedAmount, 0);
    expect(r.promotion, isNull);
  });

  test('sale only', () {
    final r = price([], sale: 45);
    expect(r.price, 45);
    expect(r.source, 'sale');
    expect(r.discountPercent, 10);
    expect(r.savedAmount, 5);
  });

  test('invalid sale price is ignored', () {
    expect(price([], sale: 60).source, 'none');
    expect(price([], sale: 0).source, 'none');
  });

  test('amount below price', () {
    final r = price([promo()]);
    expect(r.price, 45);
    expect(r.source, 'promo:p1');
    expect(r.discountPercent, 10);
    expect(r.savedAmount, 5);
    expect(r.promotion?.id, 'p1');
  });

  test('same amount on different prices, derived percent', () {
    final p = [promo(amountOff: 3)];
    final a = price(p, base: 20);
    expect(a.price, 17);
    expect(a.discountPercent, 15);
    final b = price(p, base: 12.5);
    expect(b.price, 9.5);
    expect(b.discountPercent, 24);
    final c = price(p, base: 33.99);
    expect(c.price, 30.99);
    expect(c.discountPercent, 9);
  });

  test('amount equal to price is skipped', () {
    final r = price([promo(amountOff: 50)]);
    expect(r.price, 50);
    expect(r.source, 'none');
  });

  test('amount greater than price is skipped', () {
    expect(price([promo(amountOff: 60)]).source, 'none');
  });

  test('amount leaving less than the minimum price is skipped', () {
    final r = price([promo(amountOff: 3)], base: 3.2);
    expect(r.price, 3.2);
    expect(r.source, 'none');
  });

  test('amount leaving exactly the minimum price applies', () {
    expect(price([promo(amountOff: 3)], base: 3.5).price, 0.5);
    // 1.2 − 0.7 is 0.4999… in binary; the rounded value is compared.
    expect(price([promo(amountOff: 0.7)], base: 1.2).price, 0.5);
  });

  test('better sale price wins', () {
    final r = price([promo()], sale: 40);
    expect(r.price, 40);
    expect(r.source, 'sale');
  });

  test('worse sale price loses to the promotion', () {
    final r = price([promo()], sale: 48);
    expect(r.price, 45);
    expect(r.source, 'promo:p1');
  });

  test('two promos: best wins, no stacking', () {
    final r = price([promo(), promo(id: 'p2', amountOff: 8)]);
    expect(r.price, 42);
    expect(r.source, 'promo:p2');
    expect(r.savedAmount, 8);
  });

  test('legacy percent doc still works', () {
    final r = price([promo(amountOff: null, percent: 20)]);
    expect(r.price, 40);
    expect(r.source, 'promo:p1');
    expect(r.discountPercent, 20);
  });

  test('legacy percent vs amount promo: best wins', () {
    final r = price([
      promo(amountOff: 5),
      promo(id: 'old', amountOff: null, percent: 20),
    ]);
    expect(r.price, 40);
    expect(r.source, 'promo:old');
  });

  test('amountOff takes precedence over a leftover percent', () {
    expect(price([promo(amountOff: 5, percent: 50)]).price, 45);
  });

  test('expired promo is ignored', () {
    expect(price([promo(startAt: hours(-3), endAt: hours(-1))]).source,
        'none');
  });

  test('promo ending exactly now is ignored', () {
    expect(price([promo(endAt: now)]).source, 'none');
  });

  test('scheduled promo is ignored', () {
    expect(price([promo(startAt: hours(1), endAt: hours(3))]).source, 'none');
  });

  test('promo starting exactly now applies', () {
    expect(price([promo(startAt: now)]).source, 'promo:p1');
  });

  test('inactive promo is ignored', () {
    expect(price([promo(isActive: false)]).source, 'none');
  });

  test('product not in list', () {
    expect(
        price([
          promo(productIds: ['other'])
        ]).source,
        'none');
  });

  test('rounding half up to 2 decimals', () {
    expect(price([promo(amountOff: 2.5)], base: 19.99).price, 17.49);
    // legacy: 12.35 × 0.9 = 11.115 → 11.12 (half up)
    expect(price([promo(amountOff: null, percent: 10)], base: 12.35).price,
        11.12);
    expect(roundMoney(1.005), 1.01);
  });

  test('labels and status', () {
    expect(promo(amountOff: 5).discountLabel, 'خصم 5.00 د.أ');
    expect(promo(amountOff: null, percent: 10).discountLabel, 'خصم 10%');
    expect(promo().statusAt(now), PromotionStatus.running);
    expect(promo(startAt: hours(1), endAt: hours(2)).statusAt(now),
        PromotionStatus.scheduled);
    expect(promo(endAt: now).statusAt(now), PromotionStatus.ended);
    expect(promo(isActive: false).statusAt(now), PromotionStatus.paused);
  });
}
