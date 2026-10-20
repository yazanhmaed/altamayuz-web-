import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';
import '../../data/product/product_model.dart';
import '../../widgets/product_image.dart';
import 'add_product.dart';
import 'restock_screen.dart';

/// Image URLs in the product's color order, followed by any image whose key
/// isn't in [ProductModel.colors]. Each entry is (color, url).
List<MapEntry<String, String>> productGallery(ProductModel product) {
  final result = <MapEntry<String, String>>[];
  for (final color in product.colors) {
    final url = product.imageFor(color);
    if (url != null) result.add(MapEntry(color, url));
  }
  product.imageUrls.forEach((color, url) {
    if (url.isNotEmpty && !product.colors.contains(color)) {
      result.add(MapEntry(color, url));
    }
  });
  return result;
}

/// Opens the product details as a draggable bottom sheet on phones, or a
/// centered dialog on wide screens. Always reads the live product from
/// [InventoryCubit] by [productId], and closes itself if it disappears.
Future<void> showProductDetails(BuildContext context, String productId) {
  final size = MediaQuery.sizeOf(context);
  if (size.width > 700) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: size.height * 0.9),
          child: _ProductDetailsView(productId: productId),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => _ProductDetailsView(
        productId: productId,
        scrollController: scrollController,
      ),
    ),
  );
}

class _ProductDetailsView extends StatefulWidget {
  final String productId;
  final ScrollController? scrollController;
  const _ProductDetailsView({required this.productId, this.scrollController});

  @override
  State<_ProductDetailsView> createState() => _ProductDetailsViewState();
}

class _ProductDetailsViewState extends State<_ProductDetailsView> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _deleting = false;
  bool _closed = false;

  ProductModel? _find(InventoryCubit cubit) {
    for (final p in cubit.products) {
      if (p.id == widget.productId) return p;
    }
    return null;
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  void _edit(ProductModel product) {
    final navigator = Navigator.of(context);
    _close();
    navigator.push(
      MaterialPageRoute(builder: (_) => AddProductScreen(product: product)),
    );
  }

  void _restock(ProductModel product) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RestockScreen(product: product)),
    );
  }

  Future<void> _delete(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف المنتج'),
        content: Text('هل أنت متأكد من حذف «${product.name}»؟ لا يمكن التراجع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final cubit = context.read<InventoryCubit>();
    setState(() => _deleting = true);
    await cubit.deleteProduct(product.id);
    if (!mounted) return;
    // On success the product leaves the list and the listener closes the
    // sheet; the list screen shows the success SnackBar.
    final state = cubit.state;
    if (state is InventoryError) {
      setState(() => _deleting = false);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('تعذّر حذف المنتج: ${state.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_deleting,
      child: BlocConsumer<InventoryCubit, InventoryState>(
        listenWhen: (_, __) => !_closed,
        listener: (context, _) {
          if (_find(context.read<InventoryCubit>()) == null) _close();
        },
        buildWhen: (_, current) =>
            current is InventoryLoaded ||
            current is InventorySuccess ||
            current is InventoryError,
        builder: (context, _) {
          final product = _find(context.read<InventoryCubit>());
          if (product == null) return const SizedBox(height: 120);
          return ScaffoldMessenger(
            key: _messengerKey,
            child: Scaffold(
              body: _DetailsContent(
                product: product,
                scrollController: widget.scrollController,
              ),
              bottomNavigationBar: _ActionBar(
                deleting: _deleting,
                onEdit: () => _edit(product),
                onRestock: product.colors.isEmpty ? null : () => _restock(product),
                onDelete: () => _delete(product),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetailsContent extends StatelessWidget {
  final ProductModel product;
  final ScrollController? scrollController;
  const _DetailsContent({required this.product, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.zero,
      children: [
        _Gallery(images: productGallery(product)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Pill(
                    label: product.category,
                    icon: Icons.sell_outlined,
                    background: scheme.secondaryContainer,
                    foreground: scheme.onSecondaryContainer,
                  ),
                  product.isActive
                      ? _Pill(
                          label: 'فعّال',
                          icon: Icons.visibility_outlined,
                          background: Colors.green.shade50,
                          foreground: Colors.green.shade800,
                        )
                      : _Pill(
                          label: 'مخفي',
                          icon: Icons.visibility_off_outlined,
                          background: scheme.surfaceContainerHighest,
                          foreground: scheme.onSurfaceVariant,
                        ),
                  if (product.isFeatured)
                    _Pill(
                      label: 'مميز',
                      icon: Icons.star_rounded,
                      background: Colors.amber.shade50,
                      foreground: Colors.amber.shade900,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _Prices(product: product),
              if (product.description.trim().isNotEmpty) ...[
                const _SectionTitle('الوصف'),
                Text(product.description.trim(), style: theme.textTheme.bodyMedium),
              ],
              _SectionTitle('المخزون — الكمية الكلية: ${product.totalQty}'),
              _StockBreakdown(product: product),
              if (product.sizeGuideCm.isNotEmpty) ...[
                const _SectionTitle('دليل المقاسات (سم)'),
                _SizeGuideTable(guide: product.sizeGuideCm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Gallery extends StatefulWidget {
  final List<MapEntry<String, String>> images;
  const _Gallery({required this.images});

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final cacheWidth = math.min(
      1080,
      (520 * MediaQuery.devicePixelRatioOf(context)).round(),
    );
    if (images.isEmpty) {
      return const AspectRatio(
        aspectRatio: 4 / 3,
        child: ProductImage(url: null, placeholderIconSize: 56),
      );
    }
    final page = _page.clamp(0, images.length - 1);

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => ProductImage(
              url: images[i].value,
              cacheWidth: cacheWidth,
              placeholderIconSize: 56,
            ),
          ),
          PositionedDirectional(
            top: 10,
            start: 10,
            child: _OverlayLabel(text: images[page].key),
          ),
          if (images.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == page ? Colors.white : Colors.white70,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 3),
                        ],
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

class _OverlayLabel extends StatelessWidget {
  final String text;
  const _OverlayLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _Prices extends StatelessWidget {
  final ProductModel product;
  const _Prices({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.primary,
    );
    if (!product.isOnSale) {
      return Text(_money(product.price), style: priceStyle);
    }
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(_money(product.salePrice!), style: priceStyle),
        Text(
          _money(product.price),
          style: theme.textTheme.bodyMedium?.copyWith(
            decoration: TextDecoration.lineThrough,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        _Pill(
          label: 'خصم ${product.discountPercent}%',
          background: Colors.red.shade50,
          foreground: Colors.red.shade800,
        ),
      ],
    );
  }
}

String _money(double v) => '${v.toStringAsFixed(2)} د.أ';

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;
  const _Pill({
    required this.label,
    this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockBreakdown extends StatelessWidget {
  final ProductModel product;
  const _StockBreakdown({required this.product});

  @override
  Widget build(BuildContext context) {
    if (product.colors.isEmpty) {
      return const Text(
        'لا توجد ألوان مضافة لهذا المنتج',
        style: TextStyle(color: Colors.grey, fontSize: 13),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final color in product.colors) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              color,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          if ((product.stock[color] ?? const {}).isEmpty)
            const Text(
              'لا توجد مقاسات لهذا اللون',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in product.stock[color]!.entries)
                  _StockChip(size: entry.key, qty: entry.value),
              ],
            ),
        ],
      ],
    );
  }
}

class _StockChip extends StatelessWidget {
  final String size;
  final int qty;
  const _StockChip({required this.size, required this.qty});

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (qty <= 0) {
      background = Colors.red.shade100;
      foreground = Colors.red.shade900;
    } else if (qty == 1) {
      background = Colors.amber.shade100;
      foreground = Colors.amber.shade900;
    } else {
      background = Colors.green.shade100;
      foreground = Colors.green.shade900;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$size  :  $qty',
        style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _SizeGuideTable extends StatelessWidget {
  final Map<String, double> guide;
  const _SizeGuideTable({required this.guide});

  String _cm(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const cellPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Table(
          border: TableBorder.all(
            color: scheme.outlineVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          children: [
            TableRow(
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
              children: const [
                Padding(
                  padding: cellPadding,
                  child: Text('المقاس', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Padding(
                  padding: cellPadding,
                  child: Text('طول القدم (سم)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ],
            ),
            for (final entry in guide.entries)
              TableRow(
                children: [
                  Padding(
                    padding: cellPadding,
                    child: Text(entry.key, style: const TextStyle(fontSize: 13)),
                  ),
                  Padding(
                    padding: cellPadding,
                    child: Text(_cm(entry.value), style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool deleting;
  final VoidCallback onEdit;
  final VoidCallback? onRestock;
  final VoidCallback onDelete;
  const _ActionBar({
    required this.deleting,
    required this.onEdit,
    required this.onRestock,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: deleting ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('تعديل', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (onRestock != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: deleting ? null : onRestock,
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: const Text('إضافة كمية', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: deleting ? null : onDelete,
                child: deleting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.error),
                      )
                    : const Text('حذف'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
