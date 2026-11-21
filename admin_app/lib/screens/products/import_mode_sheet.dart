import 'package:flutter/material.dart';

enum ImportMode { newProducts, stocktake }

/// Asked at the start of every Excel import — the choice is never
/// remembered, since adding products and replacing counts are very
/// different operations.
Future<ImportMode?> showImportModeSheet(BuildContext context) {
  return showModalBottomSheet<ImportMode>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('نوع الاستيراد',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const _ModeCard(
              mode: ImportMode.newProducts,
              icon: Icons.add_box_outlined,
              title: 'إضافة منتجات جديدة',
              hint: 'ينشئ المنتجات الموجودة في الملف. استخدمه لإدخال منتجات '
                  'لم تُضف للمتجر بعد.',
            ),
            const SizedBox(height: 10),
            const _ModeCard(
              mode: ImportMode.stocktake,
              icon: Icons.fact_check_outlined,
              title: 'جرد / تحديث المخزون',
              hint:
                  'يستبدل كميات المنتجات الموجودة بالكميات في الملف (عدد نهائي). '
                  'لا ينشئ منتجات، وتُراجَع الفروقات قبل التطبيق.',
            ),
          ],
        ),
      ),
    ),
  );
}

class _ModeCard extends StatelessWidget {
  final ImportMode mode;
  final IconData icon;
  final String title;
  final String hint;
  const _ModeCard({
    required this.mode,
    required this.icon,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).pop(mode),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
