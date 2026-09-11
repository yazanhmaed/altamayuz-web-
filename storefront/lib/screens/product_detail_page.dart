import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../cart/cart_controller.dart';
import '../models/public_product_model.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/product_card.dart';
import '../widgets/ui_helpers.dart';
import 'image_viewer_page.dart';

class ProductDetailPage extends StatefulWidget {
  final String productId;

  /// Already-loaded model, when the caller has one (e.g. a tap on a
  /// [ProductCard] that's already rendering from a loaded list). When null —
  /// a shared link, a fresh page load, or browser back/forward reconstructing
  /// state — the page fetches the product itself by [productId].
  final PublicProductModel? preloadedProduct;

  const ProductDetailPage({
    super.key,
    required this.productId,
    this.preloadedProduct,
  });
  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late ProductVariant _selectedVariant;
  String? _selectedSize;
  PublicProductModel? _product;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final preloaded = widget.preloadedProduct;
    if (preloaded != null) {
      _product = preloaded;
      _selectedVariant = preloaded.variants.firstWhere((v) => v.isAvailable,
          orElse: () => preloaded.variants.first);
      _loading = false;
    } else {
      _fetchProduct();
    }
  }

  Future<void> _fetchProduct() async {
    PublicProductModel? product;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .get();
      final data = doc.data();
      product =
          data == null ? null : PublicProductModel.fromProductDoc(doc.id, data);
    } catch (_) {
      product = null;
    }
    if (!mounted) return;
    setState(() {
      _product = product;
      if (product != null) {
        _selectedVariant = product.variants.firstWhere((v) => v.isAvailable,
            orElse: () => product!.variants.first);
      }
      _loading = false;
    });
  }

  void _selectColor(ProductVariant v) {
    // No-op on iOS Safari (no Vibration API); harmless elsewhere. Visual
    // feedback (swatch border + ripple) is the real signal.
    HapticFeedback.selectionClick();
    setState(() {
      _selectedVariant = v;
      _selectedSize = null;
    });
  }

  void _openImageViewer() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        // Snappy lightbox fade — explicit, rather than PageRouteBuilder's
        // implicit 300ms default (a touch slow for a media overlay).
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: ImageViewerPage(imageUrl: _selectedVariant.imageUrl),
        ),
      ),
    );
  }

  Widget _buildImage() {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: StoreImage(
                key: ValueKey(_selectedVariant.color),
                url: _selectedVariant.imageUrl,
              ),
            ),
          ),
        ),
        // Tap-to-zoom. Transparent Material + InkWell on top so the ripple
        // paints above the (opaque) photo — same pattern as ProductCard.
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openImageViewer,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context, PublicProductModel product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        PriceDisplay(
            product: product, fontSize: 22, originalFontSize: 16, decimals: 2),
        const SizedBox(height: 16),
        Text('اللون', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 8),
        Text(_selectedVariant.color,
            style: Theme.of(context).textTheme.bodyMedium),
        Wrap(
          spacing: 10,
          children: product.variants.map((v) {
            final isSelected = v.color == _selectedVariant.color;
            return Stack(
              children: [
                Opacity(
                  opacity: v.isAvailable ? 1 : 0.35,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              isSelected ? AppColors.accent : AppColors.border,
                          width: isSelected ? 2 : 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      // 56px swatch — decode at ~3x, not the stored 1600px.
                      child: StoreImage(url: v.imageUrl, cacheWidth: 170),
                    ),
                  ),
                ),
                // Ripple on top of the (opaque) swatch image. InkWell handles
                // the disabled case (onTap: null) — no ripple, non-interactive.
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: v.isAvailable ? () => _selectColor(v) : null,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text('المقاس'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _selectedVariant.sizes.entries.map((e) {
            final size = e.key;
            final isAvailable = e.value > 0;
            final isSelected = _selectedSize == size;
            return ChoiceChip(
              label: Text(size),
              selected: isSelected,
              onSelected: isAvailable
                  ? (_) => setState(() => _selectedSize = size)
                  : null,
              disabledColor: AppColors.border,
              labelStyle: TextStyle(
                  decoration: isAvailable ? null : TextDecoration.lineThrough),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _selectedSize == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  cartController.add(product, _selectedVariant, _selectedSize!);
                  showAddedToCartToast(context, product.name);
                },
          child: const Text('إضافة للسلة'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _selectedSize == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  context.push(
                    '/checkout',
                    extra: CartLine(
                      product: product,
                      variant: _selectedVariant,
                      size: _selectedSize!,
                    ),
                  );
                },
          child: const Text('اشترِ الآن'),
        ),
        // Category-based related products. Computed once from the loaded
        // product — does not react to the color/size selection above. Hides
        // itself entirely when nothing qualifies.
        _RelatedProducts(
          category: product.category,
          excludeId: product.id,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final product = _product;
    if (product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('المنتج غير موجود')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: ResponsiveCenter(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= Responsive.tabletMax) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: _buildImage()),
                    const SizedBox(width: 32),
                    Expanded(
                        flex: 5,
                        child: SingleChildScrollView(
                            child: _buildDetails(context, product))),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildImage(),
                const SizedBox(height: 16),
                _buildDetails(context, product)
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Horizontal row of up to 3 available products from the same category as the
/// current one (itself excluded). Renders nothing — no heading, no reserved
/// space — when none qualify. Same header + `SizedBox(height: 220)` +
/// 150-wide `ProductCard` sizing as the home screen's product rows.
class _RelatedProducts extends StatelessWidget {
  final String category;
  final String excludeId;
  const _RelatedProducts({required this.category, required this.excludeId});

  static const double _rowHeight = 220;
  static const double _cardWidth = 150;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .where('isActive', isEqualTo: true)
          .where('category', isEqualTo: category)
          // A small buffer over the 3 shown: the current product and any
          // out-of-stock candidates are filtered out client-side (isAvailable
          // is a derived getter, not a queryable field).
          .limit(8)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _wrap(
            context,
            ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => const SizedBox(
                width: _cardWidth,
                child: ProductCardSkeleton(),
              ),
            ),
          );
        }

        final related = snapshot.data!.docs
            .map((d) => PublicProductModel.fromProductDoc(
                  d.id,
                  d.data() as Map<String, dynamic>,
                ))
            .whereType<PublicProductModel>()
            .where((p) => p.id != excludeId && p.isAvailable)
            .take(3)
            .toList();

        if (related.isEmpty) return const SizedBox.shrink();

        return _wrap(
          context,
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: related.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: _cardWidth,
              child: ProductCard(product: related[i]),
            ),
          ),
        );
      },
    );
  }

  Widget _wrap(BuildContext context, Widget row) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 12),
          child: Text(
            'منتجات مشابهة',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SizedBox(height: _rowHeight, child: row),
      ],
    );
  }
}
