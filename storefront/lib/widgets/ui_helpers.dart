import 'package:flutter/material.dart';
import '../models/public_product_model.dart';
import '../theme/app_theme.dart';

class ProductCardSkeleton extends StatefulWidget {
  const ProductCardSkeleton({super.key});
  @override
  State<ProductCardSkeleton> createState() => _ProductCardSkeletonState();
}

class _ProductCardSkeletonState extends State<ProductCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.4 + 0.3 * (1 - (2 * _controller.value - 1).abs());
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                  child: ColoredBox(
                      color: AppColors.border.withValues(alpha: opacity))),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 12,
                        width: 100,
                        color: AppColors.border.withValues(alpha: opacity)),
                    const SizedBox(height: 8),
                    Container(
                        height: 12,
                        width: 60,
                        color: AppColors.border.withValues(alpha: opacity)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// [Image.network] that degrades gracefully when the URL is missing or fails
/// to load (some products have no image yet), instead of throwing during build.
///
/// Uses standard canvas-based `Image.network` decoding. CORS is confirmed live
/// on the Firebase Storage bucket — `gsutil cors get` matches the repo's
/// `cors.json` (origin `*`, method `GET`) — so byte fetches succeed and images
/// render correctly in every layout context, including dynamically-sized
/// `SliverGrid` cells.
///
/// `webHtmlElementStrategy: WebHtmlElementStrategy.prefer` was previously used
/// as a workaround for missing bucket CORS headers; it's removed now that CORS
/// is real, because it forces the platform-view HTML `<img>` path that renders
/// blank inside `Stack`/`StackFit.expand` grid layouts (flutter/flutter#163288,
/// #164405). Do not re-add it — if images break, diagnose fresh; the cause is
/// not CORS anymore.
///
/// [loadingBuilder] makes a still-loading image visually distinct from one that
/// failed (both otherwise look like the grey placeholder), which matters when
/// diagnosing image issues.
class StoreImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  const StoreImage({super.key, required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _ImagePlaceholder();
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _ImageLoading(),
      errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
    );
  }
}

class _ImageLoading extends StatelessWidget {
  const _ImageLoading();
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.border,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.border,
      child: Center(
          child:
              Icon(Icons.image_not_supported_outlined, color: Colors.white54)),
    );
  }
}

/// Renders a product's price: a single accent-coloured figure normally, or a
/// struck-through original next to a bold [AppColors.danger] sale figure when
/// [PublicProductModel.isOnSale] is true.
class PriceDisplay extends StatelessWidget {
  final PublicProductModel product;
  final double fontSize;
  final double? originalFontSize;
  final int decimals;
  final Color? baseColor;

  const PriceDisplay({
    super.key,
    required this.product,
    this.fontSize = 14,
    this.originalFontSize,
    this.decimals = 0,
    this.baseColor,
  });

  String _fmt(double v) => '${v.toStringAsFixed(decimals)} د.أ';

  @override
  Widget build(BuildContext context) {
    if (!product.isOnSale) {
      return Text(
        _fmt(product.price),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          color: baseColor ?? AppColors.accent,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _fmt(product.price),
          style: TextStyle(
              fontSize: originalFontSize ?? fontSize * 0.85,
              color:
                  baseColor?.withValues(alpha: 0.7) ?? AppColors.textSecondary,
              decoration: TextDecoration.lineThrough,
              decorationThickness: 2),
        ),
        const SizedBox(width: 6),
        Text(
          _fmt(product.effectivePrice),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: fontSize,
            color: AppColors.danger,
          ),
        ),
      ],
    );
  }
}

/// Small rounded `-N%` badge in [AppColors.danger], for overlaying on product
/// imagery.
class DiscountBadge extends StatelessWidget {
  final int percent;
  const DiscountBadge({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$percent%',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

void showAddedToCartToast(BuildContext context, String productName) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
              offset: Offset(0, (1 - value) * -12), child: child),
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('تمت إضافة "$productName" للسلة',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 1600), () => entry.remove());
}
