// Cart-wide quantity-discount tiers (`settings/cartDiscountTiers`).
//
// [computeCartDiscount] is the same tier-selection + clamp math as
// storefront/lib/models/cart_discount.dart and computeCartDiscount in
// functions/src/submitPublicOrder.ts — keep all three in sync. Used to
// re-apply the tiers when the owner edits a storefront order's items.
//
// Pure Dart: no Firebase imports.

class CartDiscountTier {
  final int minQuantity;
  final String type; // 'percentage' | 'fixed'
  final double value;
  const CartDiscountTier({
    required this.minQuantity,
    required this.type,
    required this.value,
  });
}

class CartDiscountResult {
  final CartDiscountTier? tier;
  final double amount;
  const CartDiscountResult({required this.tier, required this.amount});
}

/// Same rules as `sanitizeTiers` in submitPublicOrder.ts: drops
/// minQuantity < 2, percentages outside 0–100, fixed values <= 0 and anything
/// malformed, then sorts by minQuantity.
List<CartDiscountTier> sanitizeCartDiscountTiers(Object? raw) {
  final clean = <CartDiscountTier>[];
  if (raw is! List) return clean;
  for (final t in raw) {
    if (t is! Map) continue;
    final min = t['minQuantity'];
    final value = t['value'];
    final type = t['type'];
    if (min is! num || value is! num) continue;
    if (!min.isFinite || min < 2 || !value.isFinite) continue;
    if (type == 'percentage') {
      if (value < 0 || value > 100) continue;
    } else if (type == 'fixed') {
      if (value <= 0) continue;
    } else {
      continue;
    }
    clean.add(CartDiscountTier(
      minQuantity: min.toInt(),
      type: type as String,
      value: value.toDouble(),
    ));
  }
  clean.sort((a, b) => a.minQuantity.compareTo(b.minQuantity));
  return clean;
}

/// Exactly one tier applies (the highest minQuantity the total quantity
/// meets), tiers never stack, and the amount is clamped to [0, subtotal].
CartDiscountResult computeCartDiscount({
  required List<CartDiscountTier> tiers,
  required int totalQuantity,
  required double subtotal,
}) {
  final applicable = tiers.where((t) => totalQuantity >= t.minQuantity).toList()
    ..sort((a, b) => a.minQuantity.compareTo(b.minQuantity));
  if (applicable.isEmpty) {
    return const CartDiscountResult(tier: null, amount: 0);
  }
  final tier = applicable.last;
  final raw = tier.type == 'percentage'
      ? subtotal * (tier.value / 100)
      : tier.value;
  final amount = raw.clamp(0, subtotal).toDouble();
  return CartDiscountResult(tier: tier, amount: amount);
}
