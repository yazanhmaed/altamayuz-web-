import 'package:flutter/material.dart';

import '../../data/product/product_model.dart';
import '../../utils/arabic_search.dart';
import '../../utils/promotion_pricing.dart';
import '../../widgets/product_image.dart';

/// Searchable multi-select of products for a promotion. Pops the selected
/// IDs (max [kMaxPromoProducts]), or null when backed out.
class PromotionProductPicker extends StatefulWidget {
  final List<ProductModel> products;
  final List<String> initial;

  const PromotionProductPicker({
    super.key,
    required this.products,
    required this.initial,
  });

  @override
  State<PromotionProductPicker> createState() => _PromotionProductPickerState();
}

class _PromotionProductPickerState extends State<PromotionProductPicker> {
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  /// null = all categories.
  String? _category;

  List<String> get _categories =>
      ({for (final p in widget.products) p.category}.toList()..sort());

  List<ProductModel> get _visible => widget.products
      .where((p) => _category == null || p.category == _category)
      .where((p) => matchesSearch(_query, [p.name, p.category]))
      .toList();

  void _showCapReached() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('الحد الأقصى $kMaxPromoProducts منتج في العرض الواحد.'),
      ));
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length >= kMaxPromoProducts) {
        _showCapReached();
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAllInCategory() {
    var capped = false;
    setState(() {
      for (final p in widget.products.where((p) => p.category == _category)) {
        if (_selected.contains(p.id)) continue;
        if (_selected.length >= kMaxPromoProducts) {
          capped = true;
          break;
        }
        _selected.add(p.id);
      }
    });
    if (capped) _showCapReached();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    // Keep the initial order for previously selected IDs, then add new ones
    // in catalog order — so the form's preview stays stable.
    List<String> result() => [
          ...widget.initial.where(_selected.contains),
          ...widget.products.map((p) => p.id).where(
              (id) => _selected.contains(id) && !widget.initial.contains(id)),
        ];

    return Scaffold(
      appBar: AppBar(
        title: Text('المحدد: ${_selected.length} / $kMaxPromoProducts'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(result()),
            child: const Text('تم'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ابحث باسم المنتج',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: DropdownButton<String?>(
                    value: _category,
                    isExpanded: true,
                    hint: const Text('كل الفئات'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('كل الفئات')),
                      for (final c in _categories)
                        DropdownMenuItem(
                          value: c,
                          child: Text(c,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _category = v),
                  ),
                ),
                TextButton.icon(
                  onPressed: _category == null ? null : _selectAllInCategory,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('تحديد الكل في الفئة'),
                ),
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('إلغاء التحديد'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.products.isEmpty
                ? const Center(child: Text('لا توجد منتجات'))
                : visible.isEmpty
                    ? const Center(child: Text('لا توجد نتائج مطابقة'))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final p = visible[i];
                          final selected = _selected.contains(p.id);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (_) => _toggle(p.id),
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: ProductImage(
                                  url: p.colors.isEmpty
                                      ? null
                                      : p.imageFor(p.colors.first),
                                  cacheWidth: 132,
                                  placeholderIconSize: 18,
                                ),
                              ),
                            ),
                            title: Text(p.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${p.effectivePrice.toStringAsFixed(2)} د.أ'
                              '${p.isActive ? '' : ' · غير نشط'}',
                              style: theme.textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
