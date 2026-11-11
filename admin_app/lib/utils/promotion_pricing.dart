// Shared pricing rule for product-group promotions.
//
// This file is duplicated byte-for-byte in storefront/lib/pricing/ and
// admin_app/lib/utils/ — keep both in sync, and in sync with the server copy
// in functions/src/pricing.ts. All three have the same unit test cases.
//
// Rule: the customer pays the LOWEST of
//   - price,
//   - salePrice (only when 0 < salePrice < price),
//   - for every running promotion listing the product:
//       price − amountOff (JOD per unit), skipped when that would leave less
//       than [kMinDiscountedPrice]; or, for legacy documents that only have
//       `percent`, price × (1 − percent/100) as before.
// Discounts never stack. The result is rounded to 2 decimals (half up).
//
// Pure Dart: no Firebase imports, so it can be unit tested directly.

/// Legacy percentage promotions only (new ones use [Promotion.amountOff]).
const int kMinPromoPercent = 1;
const int kMaxPromoPercent = 90;
const int kMaxPromoProducts = 200;

/// A fixed-amount promotion never takes a product below this price (JOD);
/// when it would, it is not applied to that product.
const double kMinDiscountedPrice = 0.5;

enum PromotionStatus { scheduled, running, ended, paused }

extension PromotionStatusLabel on PromotionStatus {
  String get label => switch (this) {
        PromotionStatus.scheduled => 'مجدول',
        PromotionStatus.running => 'فعّال',
        PromotionStatus.ended => 'منتهٍ',
        PromotionStatus.paused => 'متوقف',
      };
}

class Promotion {
  final String id;
  final String name;

  /// JOD off each unit. The current way to define a promotion.
  final double? amountOff;

  /// Legacy: percentage off, read only when [amountOff] is absent.
  final double? percent;
  final List<String> productIds;
  final DateTime startAt;
  final DateTime endAt;
  final bool isActive;
  final String? bannerText;

  const Promotion({
    required this.id,
    required this.name,
    this.amountOff,
    this.percent,
    required this.productIds,
    required this.startAt,
    required this.endAt,
    required this.isActive,
    this.bannerText,
  });

  /// True for an old document that has `percent` but no `amountOff`.
  bool get isLegacyPercent => amountOff == null && percent != null;

  /// A usable discount: amountOff > 0, or (legacy) percent in 1–90.
  bool get hasValidDiscount {
    final a = amountOff;
    if (a != null) return a.isFinite && a > 0;
    final p = percent;
    return p != null &&
        p.isFinite &&
        p >= kMinPromoPercent &&
        p <= kMaxPromoPercent;
  }

  /// "خصم 5.00 د.أ" (or "خصم 10%" for a legacy promotion).
  String get discountLabel {
    final a = amountOff;
    if (a != null) return 'خصم ${a.toStringAsFixed(2)} د.أ';
    final p = percent ?? 0;
    return 'خصم ${p == p.roundToDouble() ? p.toStringAsFixed(0) : p}%';
  }

  /// Switched on, valid discount, and `now` inside [startAt, endAt).
  bool isRunningAt(DateTime now) =>
      isActive &&
      hasValidDiscount &&
      !now.isBefore(startAt) &&
      now.isBefore(endAt);

  /// This promotion's price for a product priced [price] (dates ignored), or
  /// null when it can't apply: invalid discount, or an amount that would
  /// leave less than [kMinDiscountedPrice].
  double? candidateFor(double price) {
    if (!hasValidDiscount) return null;
    final a = amountOff;
    if (a != null) {
      final c = roundMoney(price - a);
      return c < kMinDiscountedPrice ? null : c;
    }
    return roundMoney(price * (1 - percent! / 100));
  }

  /// Derived status. An ended promotion reads "منتهٍ" even if it was paused.
  PromotionStatus statusAt(DateTime now) {
    if (!now.isBefore(endAt)) return PromotionStatus.ended;
    if (!isActive) return PromotionStatus.paused;
    if (now.isBefore(startAt)) return PromotionStatus.scheduled;
    return PromotionStatus.running;
  }
}

class EffectivePrice {
  /// Final unit price, rounded to 2 decimals.
  final double price;

  /// 'none', 'sale', or 'promo:<id>'.
  final String source;

  /// The winning promotion, when [source] is 'promo:<id>'.
  final Promotion? promotion;

  /// round((original − price) / original × 100).
  final int discountPercent;

  /// original − price (JOD saved per unit), 0 when not discounted.
  final double savedAmount;

  const EffectivePrice({
    required this.price,
    required this.source,
    required this.promotion,
    required this.discountPercent,
    required this.savedAmount,
  });

  bool get isSale => source == 'sale';
  bool get isPromo => promotion != null;
}

/// Round half up to 2 decimals, immune to binary noise like 1.005 * 100.
double roundMoney(double value) {
  final cents = double.parse((value * 100).toStringAsPrecision(12));
  return cents.round() / 100;
}

EffectivePrice effectivePrice({
  required String productId,
  required double price,
  double? salePrice,
  required Iterable<Promotion> promotions,
  required DateTime now,
}) {
  var best = price;
  var source = 'none';
  Promotion? promotion;

  if (salePrice != null && salePrice > 0 && salePrice < price) {
    best = salePrice;
    source = 'sale';
  }

  for (final p in promotions) {
    if (!p.isRunningAt(now)) continue;
    if (!p.productIds.contains(productId)) continue;
    final candidate = p.candidateFor(price);
    if (candidate == null) continue; // would go below the minimum price
    // Strictly lower only: on a tie the existing sale price (or the first
    // promotion seen) keeps winning.
    if (candidate < best) {
      best = candidate;
      source = 'promo:${p.id}';
      promotion = p;
    }
  }

  final result = roundMoney(best);
  final discountPercent = price > 0 && result < price
      ? ((price - result) / price * 100).round()
      : 0;
  return EffectivePrice(
    price: result,
    source: source,
    promotion: promotion,
    discountPercent: discountPercent,
    savedAmount: result < price ? roundMoney(price - result) : 0,
  );
}
