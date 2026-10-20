import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';
import '../../data/product/product_model.dart';
import '../../widgets/product_image.dart';
import 'add_product.dart';
import 'import_review_screen.dart';
import 'product_details_sheet.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  @override
  void initState() {
    super.initState();
    context.read<InventoryCubit>().fetchProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المنتجات'),
        actions: [
          IconButton(
            tooltip: 'استيراد من إكسل',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () =>
                context.read<InventoryCubit>().pickAndParseExcelForImport(),
          ),
          IconButton(
            tooltip: 'تصدير إلى إكسل',
            icon: const Icon(Icons.download_outlined),
            onPressed: () =>
                context.read<InventoryCubit>().exportProductsToExcel(),
          ),
        ],
      ),
      body: BlocConsumer<InventoryCubit, InventoryState>(
        listener: (context, state) {
          if (state is InventorySuccess) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
          } else if (state is InventoryError) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
          } else if (state is InventoryImportReviewReady) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportReviewScreen()),
            );
          }
        },
        // Form/row edits from the add-product and restock screens share this
        // cubit; they don't affect the grid, so skip rebuilding for them
        // (unless the grid is still showing the loading spinner).
        buildWhen: (previous, current) =>
            previous is InventoryLoading ||
            (current is! InventoryFormChanged && current is! InventoryAddRow),
        builder: (context, state) {
          if (state is InventoryLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final cubit = context.read<InventoryCubit>();
          final products = cubit.products;
          if (products.isEmpty && state is InventoryError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('تعذّر تحميل المنتجات'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => cubit.fetchProducts(refresh: true),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (products.isEmpty) {
            return const Center(child: Text('لا توجد منتجات بعد'));
          }
          return RefreshIndicator(
            onRefresh: () => cubit.fetchProducts(refresh: true),
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.8,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return _ProductCard(
                  key: ValueKey(product.id),
                  product: product,
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddProductScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('منتج جديد'),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  const _ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gallery = productGallery(product);
    final isOutOfStock = product.totalQty <= 0;
    final isLowStock = !isOutOfStock &&
        product.stock.values
            .expand((sizes) => sizes.values)
            .any((qty) => qty <= product.lowStockThreshold);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => showProductDetails(context, product.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(
                    url: gallery.isEmpty ? null : gallery.first.value,
                  ),
                  if (isOutOfStock || isLowStock)
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: _StockBadge(outOfStock: isOutOfStock),
                    ),
                  if (!product.isActive)
                    const PositionedDirectional(
                      top: 8,
                      end: 8,
                      child: _HiddenBadge(),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small corner cue: red "نفد" when nothing is left, otherwise an amber dot
/// when some size is at or below the low-stock threshold.
class _StockBadge extends StatelessWidget {
  final bool outOfStock;
  const _StockBadge({required this.outOfStock});

  @override
  Widget build(BuildContext context) {
    if (!outOfStock) {
      return Tooltip(
        message: 'مخزون منخفض',
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.amber.shade600,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'نفد',
        style: TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _HiddenBadge extends StatelessWidget {
  const _HiddenBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off_outlined, size: 12, color: Colors.white),
          SizedBox(width: 3),
          Text('مخفي', style: TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
