import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';
import '../../data/product/product_model.dart';
import '../../widgets/labeled.dart';

class AddProductScreen extends StatefulWidget {
  final ProductModel? product;
  const AddProductScreen({super.key, this.product});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final cubit = context.read<InventoryCubit>();
    if (widget.product != null) {
      cubit.fillFormForEdit(widget.product!);
    } else {
      cubit.clearForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<InventoryCubit>();
    final isEditing = cubit.editingProduct != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'تعديل منتج' : 'إضافة منتج')),
      body: BlocListener<InventoryCubit, InventoryState>(
        listener: (context, state) {
          if (state is InventorySuccess) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
            Navigator.of(context).pop();
          } else if (state is InventoryError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Labeled(
                label: 'اسم المنتج',
                child: TextFormField(
                  controller: cubit.nameCtrl,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                ),
              ),
              const SizedBox(height: 12),
              Labeled(
                label: 'السعر',
                child: TextFormField(
                  controller: cubit.priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(height: 12),
              Labeled(
                label: 'حد التنبيه للمخزون المنخفض',
                child: TextFormField(
                  controller: cubit.lowStockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('منتج فعّال'),
                subtitle: const Text('غير الفعّال لا يظهر لأي مكان'),
                value: cubit.isActive,
                onChanged: cubit.toggleActive,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('منتج مميز'),
                subtitle: const Text('يظهر بأعلى الصفحة الرئيسية بالمتجر'),
                value: cubit.isFeatured,
                onChanged: cubit.toggleFeatured,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('الألوان والمقاسات', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: cubit.addColorRow,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة لون'),
                  ),
                ],
              ),
              ...List.generate(cubit.colorRows.length, (colorIndex) {
                final row = cubit.colorRows[colorIndex];
                final color = row.colorCtrl.text.trim();
                final existingImageUrl = row.existingImageUrl;
                final pendingImage = cubit.pendingColorImages[color];

                return Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                                if (picked != null && color.isNotEmpty) {
                                  cubit.pickColorImage(color, picked);
                                }
                              },
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.black26),
                                  borderRadius: BorderRadius.circular(8),
                                  image: pendingImage != null
                                      ? DecorationImage(
                                          image: FileImage(File(pendingImage.path)),
                                          fit: BoxFit.cover,
                                        )
                                      : existingImageUrl != null
                                          ? DecorationImage(image: NetworkImage(existingImageUrl), fit: BoxFit.cover)
                                          : null,
                                ),
                                child: pendingImage == null && existingImageUrl == null
                                    ? const Icon(Icons.add_a_photo_outlined, size: 18)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: row.colorCtrl,
                                decoration: const InputDecoration(labelText: 'اللون', border: OutlineInputBorder()),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: cubit.colorRows.length > 1 ? () => cubit.removeColorRow(colorIndex) : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(row.sizes.length, (sizeIndex) {
                          final sizeRow = row.sizes[sizeIndex];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: sizeRow.sizeCtrl,
                                    decoration: const InputDecoration(labelText: 'المقاس', border: OutlineInputBorder()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: sizeRow.qtyCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder()),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: row.sizes.length > 1
                                      ? () => cubit.removeSizeRow(colorIndex, sizeIndex)
                                      : null,
                                ),
                              ],
                            ),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => cubit.addSizeRow(colorIndex),
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة مقاس'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    cubit.saveProduct();
                  }
                },
                child: const Text('حفظ المنتج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
