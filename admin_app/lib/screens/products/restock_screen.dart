import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';
import '../../data/product/product_model.dart';

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
      body: BlocListener<InventoryCubit, InventoryState>(
        listener: (context, state) {
          if (state is InventorySuccess) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
            Navigator.of(context).pop();
          } else if (state is InventoryError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...List.generate(cubit.restockRows.length, (index) {
              final row = cubit.restockRows[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: row.colorCtrl,
                        decoration: const InputDecoration(labelText: 'اللون', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: row.sizeCtrl,
                        decoration: const InputDecoration(labelText: 'المقاس', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: row.qtyCtrl,
                        keyboardType: TextInputType.number,
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
              onPressed: cubit.submitRestock,
              child: const Text('تأكيد الإضافة'),
            ),
          ],
        ),
      ),
    );
  }
}
