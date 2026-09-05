import 'package:flutter/material.dart';
import '../cart/cart_controller.dart';
import '../models/public_product_model.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/ui_helpers.dart';
import 'checkout_page.dart';

class ProductDetailPage extends StatefulWidget {
  final PublicProductModel product;
  const ProductDetailPage({super.key, required this.product});
  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late ProductVariant _selectedVariant;
  String? _selectedSize;

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.product.variants.firstWhere((v) => v.isAvailable, orElse: () => widget.product.variants.first);
  }

  void _selectColor(ProductVariant v) {
    setState(() {
      _selectedVariant = v;
      _selectedSize = null;
    });
  }

  Widget _buildImage() {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOut,
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: Image.network(
            _selectedVariant.imageUrl,
            key: ValueKey(_selectedVariant.color),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.border),
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final product = widget.product;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
        Text('${product.price.toStringAsFixed(2)} د.أ', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        const Text('اللون'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: product.variants.map((v) {
            final isSelected = v.color == _selectedVariant.color;
            return GestureDetector(
              onTap: v.isAvailable ? () => _selectColor(v) : null,
              child: Opacity(
                opacity: v.isAvailable ? 1 : 0.35,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? AppColors.accent : AppColors.border, width: isSelected ? 2 : 1),
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.network(v.imageUrl, fit: BoxFit.cover)),
                ),
              ),
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
              onSelected: isAvailable ? (_) => setState(() => _selectedSize = size) : null,
              disabledColor: AppColors.border,
              labelStyle: TextStyle(decoration: isAvailable ? null : TextDecoration.lineThrough),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _selectedSize == null
                    ? null
                    : () {
                        cartController.add(product, _selectedVariant, _selectedSize!);
                        showAddedToCartToast(context, product.name);
                      },
                child: const Text('إضافة للسلة'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _selectedSize == null
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CheckoutPage(
                              buyNowItem: CartLine(
                                product: product,
                                variant: _selectedVariant,
                                size: _selectedSize!,
                              ),
                            ),
                          ),
                        ),
                child: const Text('اشترِ الآن'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.product.name)),
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
                    Expanded(flex: 5, child: SingleChildScrollView(child: _buildDetails(context))),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [_buildImage(), const SizedBox(height: 16), _buildDetails(context)],
            );
          },
        ),
      ),
    );
  }
}
