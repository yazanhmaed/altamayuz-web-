import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';

/// Review step shown after [InventoryCubit.pickAndParseExcelForImport]
/// parses an Excel file in memory (no Firestore/Storage writes yet). Shows
/// every parsed product and every one of its colors, with existing images
/// (for products that already exist) pre-loaded, so the admin can pick or
/// replace any color's image before [InventoryCubit.confirmImport] actually
/// commits anything.
class ImportReviewScreen extends StatelessWidget {
  const ImportReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة الاستيراد')),
      body: BlocConsumer<InventoryCubit, InventoryState>(
        listener: (context, state) {
          if (state is InventorySuccess) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
            Navigator.of(context).pop();
          } else if (state is InventoryError) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          final cubit = context.read<InventoryCubit>();
          final isSaving = state is InventoryLoading;
          final items = cubit.pendingImportItems;
          final errors = cubit.pendingImportErrors;

          return Column(
            children: [
              if (errors.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.orange.shade800, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'تم تخطي ${errors.length} منتج بسبب أخطاء:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final e in errors)
                        Text('• $e',
                            style: TextStyle(
                                fontSize: 12, color: Colors.orange.shade900)),
                    ],
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('لا توجد منتجات للمراجعة'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) =>
                            _ProductReviewCard(product: items[i]),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSaving
                              ? null
                              : () {
                                  cubit.cancelImport();
                                  Navigator.of(context).pop();
                                },
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: isSaving || items.isEmpty
                              ? null
                              : () => cubit.confirmImport(),
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('تأكيد الاستيراد'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductReviewCard extends StatelessWidget {
  final PendingImportProduct product;
  const _ProductReviewCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = product.colors.toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(product.name, style: theme.textTheme.titleMedium),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: product.isNew
                        ? Colors.blue.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: product.isNew
                          ? Colors.blue.shade300
                          : Colors.green.shade300,
                    ),
                  ),
                  child: Text(
                    product.isNew ? 'جديد' : 'موجود',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: product.isNew
                          ? Colors.blue.shade800
                          : Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'السعر: ${product.price != null ? '${product.price!.toStringAsFixed(2)} د.أ' : 'بدون تغيير'}'
              '  —  التصنيف: ${product.category ?? 'بدون تغيير'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in colors)
                  _ColorImageSlot(product: product, color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorImageSlot extends StatefulWidget {
  final PendingImportProduct product;
  final String color;
  const _ColorImageSlot({required this.product, required this.color});

  @override
  State<_ColorImageSlot> createState() => _ColorImageSlotState();
}

class _ColorImageSlotState extends State<_ColorImageSlot> {
  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;
    context
        .read<InventoryCubit>()
        .setPendingImportImage(widget.product.name, widget.color, picked);
  }

  @override
  Widget build(BuildContext context) {
    final pendingImage = widget.product.pendingImages[widget.color];
    final existingUrl = widget.product.existingImageUrls[widget.color];
    final hasImage = pendingImage != null ||
        (existingUrl != null && existingUrl.isNotEmpty);

    return SizedBox(
      width: 96,
      child: Column(
        children: [
          Text(widget.color,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 72,
              height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: pendingImage != null
                  ? _MemoryPreview(file: pendingImage)
                  : (existingUrl != null && existingUrl.isNotEmpty)
                      ? Image.network(existingUrl, fit: BoxFit.cover)
                      : const Icon(Icons.image_not_supported_outlined,
                          size: 24, color: Colors.black38),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _pickImage,
            child: Text(
              hasImage ? 'تغيير الصورة' : 'اختر صورة',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a freshly-picked [XFile] via bytes + [Image.memory] — never
/// `FileImage(File(...))`, which doesn't work on Flutter Web.
class _MemoryPreview extends StatelessWidget {
  final XFile file;
  const _MemoryPreview({required this.file});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}
