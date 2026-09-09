import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cart_discount.dart';

/// One-time read of the cart-wide quantity-discount tiers from
/// `settings/cartDiscountTiers` (mirrors the `settings/owner` pattern). The
/// config changes rarely, so this is a plain `get()`, not a live stream.
///
/// A missing document, or a missing/empty/malformed `tiers` field, is treated
/// as "no tiers configured" and returns an empty list — never an error.
/// Individual malformed tier entries are skipped rather than failing the whole
/// read; the authoritative validation lives server-side in `submitPublicOrder`.
Future<List<CartDiscountTier>> loadCartDiscountTiers() async {
  final snap = await FirebaseFirestore.instance
      .collection('settings')
      .doc('cartDiscountTiers')
      .get();

  final raw = snap.data()?['tiers'];
  if (raw is! List) return const [];

  final tiers = <CartDiscountTier>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    try {
      tiers.add(CartDiscountTier.fromMap(Map<String, dynamic>.from(entry)));
    } catch (_) {
      // Skip a malformed tier rather than breaking checkout.
    }
  }
  return tiers;
}
