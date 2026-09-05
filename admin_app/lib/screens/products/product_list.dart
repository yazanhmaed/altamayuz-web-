import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';
import '../../data/product/product_model.dart';
import 'add_product.dart';
import 'restock_screen.dart';

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
            onPressed: () => context.read<InventoryCubit>().importProductsFromExcel(),
          ),
          IconButton(
            tooltip: 'تصدير إلى إكسل',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => context.read<InventoryCubit>().exportProductsToExcel(),
          ),
        ],
      ),
      body: BlocConsumer<InventoryCubit, InventoryState>(
        listener: (context, state) {
          if (state is InventorySuccess) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          } else if (state is InventoryError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          if (state is InventoryLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = context.read<InventoryCubit>().products;
          if (products.isEmpty) {
            return const Center(child: Text('لا توجد منتجات بعد'));
          }
          return RefreshIndicator(
            onRefresh: () => context.read<InventoryCubit>().fetchProducts(refresh: true),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _ProductTile(product: products[index]),
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

class _ProductTile extends StatelessWidget {
  final ProductModel product;
  const _ProductTile({required this.product});

  @override
  Widget build(BuildContext context) {
    final isLowStock = product.totalQty <= product.lowStockThreshold;
    return Card(
      child: ListTile(
        title: Text(product.name),
        subtitle: Text(
          '${product.price.toStringAsFixed(2)} — الكمية الكلية: ${product.totalQty}'
          '${product.isFeatured ? ' — مميز' : ''}'
          '${!product.isActive ? ' — غير فعّال' : ''}',
          style: TextStyle(color: isLowStock ? Colors.red : null),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'إضافة كمية',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RestockScreen(product: product)),
              ),
            ),
            IconButton(
              tooltip: 'تعديل',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AddProductScreen(product: product)),
              ),
            ),
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('حذف المنتج'),
                    content: Text('هل أنت متأكد من حذف "${product.name}"؟'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  context.read<InventoryCubit>().deleteProduct(product.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
