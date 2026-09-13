import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';
import '../../data/product/product_model.dart';
import '../../utils/arabic_digits.dart';

class RestockScreen extends StatefulWidget {
  final ProductModel product;
  const RestockScreen({super.key, required this.product});

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {
  @override
  void initState() {
    super.initState();
    context.read<InventoryCubit>().loadProductForRestock(widget.product);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<InventoryCubit>();

    return Scaffold(
      appBar: AppBar(title: Text('إضافة كمية — ${widget.product.name}')),
      body: BlocConsumer<InventoryCubit, InventoryState>(
        listener: (context, state) {
          if (state is InventorySuccess) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
            Navigator.of(context).pop();
          } else if (state is InventoryError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
        final isSaving = state is InventoryLoading;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...List.generate(cubit.restockRows.length, (index) {
              final row = cubit.restockRows[index];
              final sizes = widget.product.stock[row.colorCtrl.text]?.keys.toList() ?? [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: row.colorCtrl.text.isNotEmpty ? row.colorCtrl.text : null,
                        decoration: const InputDecoration(labelText: 'اللون', border: OutlineInputBorder()),
                        items: widget.product.colors.isEmpty
                            ? null
                            : widget.product.colors
                                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                        hint: widget.product.colors.isEmpty
                            ? const Text('لا توجد ألوان مضافة لهذا المنتج')
                            : null,
                        onChanged: widget.product.colors.isEmpty
                            ? null
                            : (value) {
                                if (value != null) cubit.setRestockRowColor(index, value);
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: row.sizeCtrl.text.isNotEmpty ? row.sizeCtrl.text : null,
                        decoration: const InputDecoration(labelText: 'المقاس', border: OutlineInputBorder()),
                        items: sizes.isEmpty
                            ? null
                            : sizes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        hint: sizes.isEmpty
                            ? Text(row.colorCtrl.text.isEmpty
                                ? 'اختر لونًا أولًا'
                                : 'لا توجد مقاسات لهذا اللون')
                            : null,
                        onChanged: sizes.isEmpty
                            ? null
                            : (value) {
                                if (value != null) cubit.setRestockRowSize(index, value);
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: row.qtyCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ArabicDigitsInputFormatter()],
                        decoration: const InputDecoration(labelText: 'الكمية المضافة', border: OutlineInputBorder()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: cubit.restockRows.length > 1 ? () => cubit.removeRestockRow(index) : null,
                    ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: cubit.addRestockRow,
              icon: const Icon(Icons.add),
              label: const Text('إضافة صف'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: isSaving ? null : cubit.submitRestock,
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('تأكيد الإضافة'),
            ),
          ],
        );
        },
      ),
    );
  }
}
