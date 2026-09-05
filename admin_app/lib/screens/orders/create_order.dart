import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/order/order_cubit.dart';
import '../../cubit/order/order_state.dart';
import '../../data/order/pick_result_model.dart';
import '../../data/product/product_model.dart';
import '../../widgets/labeled.dart';

class CreateOrderScreen extends StatelessWidget {
  const CreateOrderScreen({super.key});

  Future<void> _openItemPicker(BuildContext context) async {
    final inventoryCubit = context.read<InventoryCubit>();
    final orderCubit = context.read<OrderCubit>();
    await inventoryCubit.fetchProducts();

    if (!context.mounted) return;
    final pick = await showDialog<_PickedItem>(
      context: context,
      builder: (_) => _ItemPickerDialog(products: inventoryCubit.products),
    );
    if (pick != null) {
      orderCubit.addItem(pick.pickResult, pick.quantity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<OrderCubit>();
    final isEditing = cubit.editingOrder != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'تعديل طلب' : 'طلب جديد')),
      body: BlocListener<OrderCubit, OrderState>(
        listener: (context, state) {
          if (state is OrderSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
            Navigator.of(context).pop();
          } else if (state is OrderError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Labeled(
              label: 'اسم الزبون',
              child: TextFormField(
                controller: cubit.customerNameCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 12),
            Labeled(
              label: 'رقم الهاتف',
              child: TextFormField(
                controller: cubit.customerPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 12),
            Labeled(
              label: 'المدينة',
              child: TextFormField(
                controller: cubit.addressCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 12),
            Labeled(
              label: 'المنطقة',
              child: TextFormField(
                controller: cubit.areaCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 12),
            Labeled(
              label: 'تفاصيل العنوان',
              child: TextFormField(
                controller: cubit.streetCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 12),
            Labeled(
              label: 'الوجهة (اختياري)',
              child: TextFormField(
                controller: cubit.destinationCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 12),
            Labeled(
              label: 'تاريخ التسليم (اختياري)',
              child: TextFormField(
                controller: cubit.deliveryDateCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('القطع', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openItemPicker(context),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة قطعة'),
                ),
              ],
            ),
            ...List.generate(cubit.selectedItems.length, (index) {
              final item = cubit.selectedItems[index];
              return ListTile(
                dense: true,
                title: Text('${item.productName ?? item.productId} — ${item.color} — مقاس ${item.size}'),
                subtitle: Text('الكمية: ${item.quantity}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => cubit.removeItem(index),
                ),
              );
            }),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: cubit.submitOrder,
              child: const Text('حفظ الطلب'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedItem {
  final PickResult pickResult;
  final int quantity;
  _PickedItem(this.pickResult, this.quantity);
}

class _ItemPickerDialog extends StatefulWidget {
  final List<ProductModel> products;
  const _ItemPickerDialog({required this.products});

  @override
  State<_ItemPickerDialog> createState() => _ItemPickerDialogState();
}

class _ItemPickerDialogState extends State<_ItemPickerDialog> {
  ProductModel? _selectedProduct;
  String? _selectedColor;
  String? _selectedSize;
  final _qtyCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختيار قطعة'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<ProductModel>(
              value: _selectedProduct,
              decoration: const InputDecoration(labelText: 'المنتج'),
              items: [
                for (final p in widget.products) DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (value) => setState(() {
                _selectedProduct = value;
                _selectedColor = null;
                _selectedSize = null;
              }),
            ),
            if (_selectedProduct != null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedColor,
                decoration: const InputDecoration(labelText: 'اللون'),
                items: [
                  for (final c in _selectedProduct!.colors)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (value) => setState(() {
                  _selectedColor = value;
                  _selectedSize = null;
                }),
              ),
            ],
            if (_selectedColor != null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedSize,
                decoration: const InputDecoration(labelText: 'المقاس'),
                items: [
                  for (final entry in (_selectedProduct!.stock[_selectedColor] ?? {}).entries)
                    DropdownMenuItem(value: entry.key, child: Text('${entry.key} (متوفر: ${entry.value})')),
                ],
                onChanged: (value) => setState(() => _selectedSize = value),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الكمية'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _selectedProduct == null || _selectedColor == null || _selectedSize == null
              ? null
              : () {
                  final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
                  Navigator.pop(
                    context,
                    _PickedItem(
                      PickResult(
                        productId: _selectedProduct!.id,
                        productName: _selectedProduct!.name,
                        color: _selectedColor!,
                        size: _selectedSize!,
                        sku: '${_selectedProduct!.id}-$_selectedColor-$_selectedSize',
                      ),
                      qty,
                    ),
                  );
                },
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}
