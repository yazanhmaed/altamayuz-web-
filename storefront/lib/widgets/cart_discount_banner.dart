import 'package:flutter/material.dart';

import '../data/cart_discount_repository.dart';
import '../models/cart_discount.dart';
import '../theme/app_theme.dart';

/// Promotional bar at the very top of the home screen announcing the cart-wide
/// quantity-discount tiers, so a browsing customer discovers the promo before
/// opening the cart. Static — no tap, no dismiss.
///
/// Reads the tiers via [loadCartDiscountTiers] (the same one-time loader the
/// checkout page uses) and renders nothing at all until/unless there is at
/// least one valid tier — matching the home page's "hide entirely, no gap"
/// convention for conditional sections.
class CartDiscountBanner extends StatefulWidget {
  const CartDiscountBanner({super.key, this.debugTiers});

  /// Test-only override: when set, these tiers are rendered directly and the
  /// Firestore read is skipped (which can't run without Firebase init in a
  /// widget test). Never pass this in app code.
  @visibleForTesting
  final List<CartDiscountTier>? debugTiers;

  @override
  State<CartDiscountBanner> createState() => _CartDiscountBannerState();
}

class _CartDiscountBannerState extends State<CartDiscountBanner> {
  List<CartDiscountTier> _tiers = const [];

  @override
  void initState() {
    super.initState();
    if (widget.debugTiers != null) {
      _tiers = widget.debugTiers!;
      return;
    }
    loadCartDiscountTiers().then((tiers) {
      if (mounted) setState(() => _tiers = tiers);
    }).catchError((_) {
      // Config read failed — just don't show the banner.
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_tiers.isEmpty) return const SizedBox.shrink();

    // Show the full ladder, lowest tier first.
    final tiers = [..._tiers]
      ..sort((a, b) => a.minQuantity.compareTo(b.minQuantity));

    return Container(
      width: double.infinity,
      color: AppColors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.local_offer, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            // A Column, not a Row: the heading + one Text per tier must stack
            // and wrap on their own lines. Multiple non-flexible Texts in a
            // Row overflow at ~320px (RenderFlex).
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'خصومات على الكمية',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                for (final tier in tiers)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      tier.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
