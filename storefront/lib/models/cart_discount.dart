class CartDiscountTier {
  final int minQuantity;
  final String type; // 'percentage' | 'fixed'
  final double value;
  const CartDiscountTier({
    required this.minQuantity,
    required this.type,
    required this.value,
  });

  factory CartDiscountTier.fromMap(Map<String, dynamic> map) => CartDiscountTier(
        minQuantity: (map['minQuantity'] as num).toInt(),
        type: map['type'] as String,
        value: (map['value'] as num).toDouble(),
      );

  /// Arabic one-line description of this tier, e.g. "قطعتان فأكثر: خصم 10%" or
  /// "5 قطع فأكثر: خصم 15 د.أ". Shared phrasing so every place that describes a
  /// tier in words (the home promo banner, and any future UI) stays consistent.
  String get label {
    // "قطعتان" is the correct Arabic dual form for exactly 2.
    final quantity = minQuantity == 2 ? 'قطعتان' : '$minQuantity قطع';
    final amount = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
    final discount =
        type == 'percentage' ? 'خصم $amount%' : 'خصم $amount د.أ';
    return '$quantity فأكثر: $discount';
  }
}

class CartDiscountResult {
  final CartDiscountTier? tier;
  final double amount;
  const CartDiscountResult({required this.tier, required this.amount});
}

/// Pure calculation, shared by every place in the storefront that needs to
/// show or reason about the cart-wide discount — do not reimplement this
/// tier-selection/clamp logic anywhere else.
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
