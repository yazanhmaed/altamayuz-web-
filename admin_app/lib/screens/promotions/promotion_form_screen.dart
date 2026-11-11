import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';
import '../../cubit/promotions/promotions_cubit.dart';
import '../../data/product/product_model.dart';
import '../../utils/arabic_digits.dart';
import '../../utils/promotion_pricing.dart';
import '../../widgets/labeled.dart';
import '../../widgets/product_image.dart';
import 'promotion_product_picker.dart';
import 'promotions_screen.dart' show formatPromoDate;

String _money(double v) => '${v.toStringAsFixed(2)} د.أ';

/// Arabic decimal separator (٫) and comma → '.'.
class _DecimalSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text.replaceAll('٫', '.').replaceAll(',', '.');
    return t == newValue.text ? newValue : newValue.copyWith(text: t);
  }
}

/// A promotion for evaluating prices regardless of dates/switch.
Promotion _draftWithAmount(double amount, List<String> productIds) => Promotion(
      id: '_draft',
      name: '',
      amountOff: amount,
      productIds: productIds,
      startAt: DateTime(2000),
      endAt: DateTime(3000),
      isActive: true,
    );

/// Create (editing == null) or edit a promotion.
class PromotionFormScreen extends StatefulWidget {
  final Promotion? editing;
  const PromotionFormScreen({super.key, this.editing});

  @override
  State<PromotionFormScreen> createState() => _PromotionFormScreenState();
}

class _PromotionFormScreenState extends State<PromotionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.editing?.name);
  // A legacy percentage promotion starts empty: the owner enters an amount
  // and saving removes `percent`.
  late final _amountCtrl = TextEditingController(
    text: widget.editing?.amountOff?.toStringAsFixed(2) ?? '',
  );
  late final _bannerCtrl =
      TextEditingController(text: widget.editing?.bannerText ?? '');
  late DateTime? _startAt = widget.editing?.startAt;
  late DateTime? _endAt = widget.editing?.endAt;
  late bool _isActive = widget.editing?.isActive ?? true;
  late List<String> _productIds = [...?widget.editing?.productIds];
  bool _triedSave = false;

  @override
  void initState() {
    super.initState();
    context.read<InventoryCubit>().fetchProducts();
    _amountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _bannerCtrl.dispose();
    super.dispose();
  }

  /// The typed amount (JOD per unit), or null when empty/invalid/≤ 0.
  double? get _amount {
    final v = double.tryParse(normalizeDigits(_amountCtrl.text.trim()));
    return (v == null || !v.isFinite || v <= 0) ? null : roundMoney(v);
  }

  /// Selected products (that still exist) the amount can't apply to:
  /// price − amount would fall below [kMinDiscountedPrice].
  List<ProductModel> _skipped(List<ProductModel> products) {
    final amount = _amount;
    if (amount == null) return const [];
    final draft = _draftWithAmount(amount, _productIds);
    final selected = _productIds.toSet();
    return [
      for (final p in products)
        if (selected.contains(p.id) && draft.candidateFor(p.price) == null) p,
    ];
  }

  /// True when the products are loaded, some are selected, and the amount
  /// applies to none of them.
  bool _appliesToNone(List<ProductModel> products) {
    final selected = _productIds.toSet();
    final known = products.where((p) => selected.contains(p.id)).length;
    return known > 0 && _skipped(products).length == known;
  }

  bool get _datesInvalid =>
      _startAt != null && _endAt != null && !_endAt!.isAfter(_startAt!);

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final base = initial ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _openPicker(List<ProductModel> products) async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => PromotionProductPicker(
          products: products,
          initial: _productIds,
        ),
      ),
    );
    if (picked != null) setState(() => _productIds = picked);
  }

  Future<void> _save() async {
    setState(() => _triedSave = true);
    final formOk = _formKey.currentState!.validate();
    final products = context.read<InventoryCubit>().products;
    if (!formOk ||
        _startAt == null ||
        _endAt == null ||
        _datesInvalid ||
        _productIds.isEmpty ||
        _appliesToNone(products)) {
      return;
    }
    final draft = Promotion(
      id: widget.editing?.id ?? '',
      name: _nameCtrl.text.trim(),
      amountOff: _amount,
      productIds: _productIds,
      startAt: _startAt!,
      endAt: _endAt!,
      isActive: _isActive,
      bannerText: _bannerCtrl.text.trim(),
    );
    final ok = await context
        .read<PromotionsCubit>()
        .save(draft, id: widget.editing?.id);
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final busy = context.select((PromotionsCubit c) => c.state.busy);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'عرض جديد' : 'تعديل العرض'),
      ),
      body: BlocBuilder<InventoryCubit, InventoryState>(
        buildWhen: (_, s) =>
            s is InventoryLoaded ||
            s is InventoryLoading ||
            s is InventoryError,
        builder: (context, invState) {
          final products = context.read<InventoryCubit>().products;
          final loadingProducts =
              invState is InventoryLoading && products.isEmpty;

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Labeled(
                  label: 'اسم العرض',
                  child: TextFormField(
                    controller: _nameCtrl,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'مثال: خصم نهاية الموسم',
                      counterText: '',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'أدخل اسم العرض'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Labeled(
                  label: 'قيمة الخصم (د.أ) لكل قطعة',
                  child: TextFormField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    inputFormatters: [
                      ArabicDigitsInputFormatter(),
                      _DecimalSeparatorFormatter(),
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'مثال: 3.00',
                      suffixText: 'د.أ',
                    ),
                    validator: (_) =>
                        _amount == null ? 'أدخل قيمة أكبر من صفر' : null,
                  ),
                ),
                if (widget.editing?.isLegacyPercent == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'هذا عرض قديم ب${widget.editing!.discountLabel}. أدخل قيمة '
                      'الخصم بالدينار لتحويله؛ ستُحذف النسبة عند الحفظ.',
                      style:
                          TextStyle(color: Colors.blue.shade800, fontSize: 12),
                    ),
                  ),
                Builder(builder: (context) {
                  final skipped = _skipped(products);
                  if (skipped.isEmpty) return const SizedBox.shrink();
                  final names = skipped.take(3).map((p) => p.name).join('، ');
                  final more = skipped.length > 3 ? '…' : '';
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'لن يُطبَّق على ${skipped.length} منتج (السعر بعد الخصم '
                      'أقل من ${_money(kMinDiscountedPrice)}): $names$more',
                      style: TextStyle(
                          color: Colors.orange.shade800, fontSize: 12),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                _DateField(
                  label: 'يبدأ في',
                  value: _startAt,
                  error: _triedSave && _startAt == null
                      ? 'اختر تاريخ البداية'
                      : null,
                  warning: _startAt != null &&
                          _startAt!.isBefore(now) &&
                          widget.editing?.startAt != _startAt
                      ? 'تاريخ البداية في الماضي — سيبدأ العرض فور الحفظ.'
                      : null,
                  onTap: () async {
                    final v = await _pickDateTime(_startAt);
                    if (v != null) setState(() => _startAt = v);
                  },
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: 'ينتهي في',
                  value: _endAt,
                  error: _triedSave && _endAt == null
                      ? 'اختر تاريخ النهاية'
                      : _datesInvalid
                          ? 'يجب أن يكون تاريخ النهاية بعد البداية'
                          : null,
                  onTap: () async {
                    final v = await _pickDateTime(
                        _endAt ?? _startAt?.add(const Duration(days: 7)));
                    if (v != null) setState(() => _endAt = v);
                  },
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('العرض مفعّل'),
                  subtitle: const Text('أوقفه في أي وقت دون حذفه'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 4),
                Labeled(
                  label: 'نص الشريط في المتجر (اختياري)',
                  child: TextFormField(
                    controller: _bannerCtrl,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'يظهر بدل اسم العرض عند وجود عرض واحد فعّال',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'المنتجات (${_productIds.length} / $kMaxPromoProducts)',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          loadingProducts ? null : () => _openPicker(products),
                      icon: const Icon(Icons.checklist),
                      label: const Text('اختيار المنتجات'),
                    ),
                  ],
                ),
                if (_triedSave && _productIds.isEmpty)
                  Text(
                    'اختر منتجًا واحدًا على الأقل',
                    style: TextStyle(color: theme.colorScheme.error),
                  )
                else if (_productIds.isNotEmpty && _appliesToNone(products))
                  Text(
                    'قيمة الخصم لا تنطبق على أي من المنتجات المختارة',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                if (loadingProducts)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (invState is InventoryError && products.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Expanded(child: Text('تعذّر تحميل المنتجات')),
                        TextButton(
                          onPressed: () => context
                              .read<InventoryCubit>()
                              .fetchProducts(refresh: true),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                else
                  _Preview(
                    products: products,
                    productIds: _productIds,
                    amount: _amount,
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : _save,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('حفظ العرض'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final String? error;
  final String? warning;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.error,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    return Labeled(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                errorText: error,
                suffixIcon: const Icon(Icons.event_outlined),
              ),
              child: Text(
                value == null ? 'اختر التاريخ والوقت' : formatPromoDate(value!),
              ),
            ),
          ),
          if (warning != null && error == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                warning!,
                style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Selected products with old → new price under this promotion alone (shared
/// rule) and the saved amount, flagging the ones whose own sale price is
/// already better and the ones the amount can't apply to.
class _Preview extends StatelessWidget {
  final List<ProductModel> products;
  final List<String> productIds;
  final double? amount;

  const _Preview({
    required this.products,
    required this.productIds,
    required this.amount,
  });

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
      );

  @override
  Widget build(BuildContext context) {
    if (productIds.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final byId = {for (final p in products) p.id: p};
    final draft = amount == null ? null : _draftWithAmount(amount!, productIds);
    final now = DateTime.now();

    return Column(
      children: [
        for (final id in productIds)
          Builder(builder: (context) {
            final p = byId[id];
            if (p == null) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline),
                title: const Text('منتج محذوف'),
                subtitle:
                    Text(id, maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            }
            final r = effectivePrice(
              productId: p.id,
              price: p.price,
              salePrice: p.salePrice,
              promotions: draft == null ? const [] : [draft],
              now: now,
            );
            final skipped =
                draft != null && draft.candidateFor(p.price) == null;
            final saleBetter = draft != null && !skipped && r.isSale;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: ProductImage(
                    url: p.colors.isEmpty ? null : p.imageFor(p.colors.first),
                    cacheWidth: 120,
                    placeholderIconSize: 18,
                  ),
                ),
              ),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (r.price < p.price)
                    Text(
                      _money(p.price),
                      style: const TextStyle(
                          decoration: TextDecoration.lineThrough),
                    ),
                  Text(
                    _money(r.price),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: r.price < p.price ? Colors.red.shade700 : null,
                    ),
                  ),
                  if (r.isPromo)
                    _tag('توفير ${_money(r.savedAmount)}', Colors.green.shade50,
                        Colors.green.shade800),
                  if (saleBetter)
                    _tag(
                        'السعر الحالي أفضل',
                        theme.colorScheme.secondaryContainer,
                        theme.colorScheme.onSecondaryContainer),
                  if (skipped)
                    _tag('لا يُطبَّق (أقل من ${_money(kMinDiscountedPrice)})',
                        Colors.orange.shade50, Colors.orange.shade800),
                ],
              ),
            );
          }),
      ],
    );
  }
}
