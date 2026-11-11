import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config/jordan_governorates.dart';
import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';
import '../../cubit/order/order_cubit.dart';
import '../../cubit/order/order_state.dart';
import '../../cubit/promotions/promotions_cubit.dart';
import '../../data/customer/customer_model.dart';
import '../../data/order/pick_result_model.dart';
import '../../data/product/product_model.dart';
import '../../utils/arabic_digits.dart';
import '../../utils/jordan_phone.dart';
import '../../utils/promotion_pricing.dart';
import '../../widgets/labeled.dart';
import 'widgets/customer_phone_field.dart';
import 'widgets/qr_scanner_screen.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

/// Dropdown value for "أخرى (كتابة يدوية)" — never stored; the typed city is.
const _kOtherCity = '__other__';

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();

  // ---- governorate: one of kJordanGovernorates, or "أخرى" + free text.
  // cubit.addressCtrl always holds the final value.
  final _customCityCtrl = TextEditingController();
  String? _cityChoice;

  /// Bumped to rebuild the dropdown when the city is set in code.
  int _cityFieldVersion = 0;

  /// E.164 phone of the customer whose data was filled from a suggestion;
  /// drives the "تم تعبئة بيانات العميل" chip.
  String? _filledPhone;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<OrderCubit>();
    _setCity(cubit, cubit.addressCtrl.text, rebuild: false);
    cubit.customerPhoneCtrl.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    context.read<OrderCubit>().customerPhoneCtrl.removeListener(_onPhoneChanged);
    _customCityCtrl.dispose();
    super.dispose();
  }

  /// Typing another phone hides the chip (the filled fields stay as they are).
  void _onPhoneChanged() {
    if (_filledPhone == null) return;
    final phone = context.read<OrderCubit>().customerPhoneCtrl.text;
    if (normalizePhoneE164(phone) != _filledPhone) {
      setState(() => _filledPhone = null);
    }
  }

  void _setCity(OrderCubit cubit, String city, {bool rebuild = true}) {
    final c = city.trim();
    void apply() {
      if (c.isEmpty) {
        _cityChoice = null;
        _customCityCtrl.clear();
      } else if (kJordanGovernorates.contains(c)) {
        _cityChoice = c;
        _customCityCtrl.clear();
      } else {
        _cityChoice = _kOtherCity;
        _customCityCtrl.text = c;
      }
      cubit.addressCtrl.text = c;
      _cityFieldVersion++;
    }

    rebuild ? setState(apply) : apply();
  }

  void _fillFromCustomer(OrderCubit cubit, CustomerModel c) {
    final phone = c.phone.isNotEmpty ? c.phone : c.id;
    cubit.customerNameCtrl.text = c.name;
    cubit.customerPhoneCtrl.text = jordanPhoneToLocal(phone);
    cubit.areaCtrl.text = c.area;
    cubit.streetCtrl.text = c.street;
    _setCity(cubit, c.city);
    setState(() => _filledPhone = normalizePhoneE164(phone));
  }

  void _clearFilled(OrderCubit cubit) {
    cubit.customerNameCtrl.clear();
    cubit.customerPhoneCtrl.clear();
    cubit.areaCtrl.clear();
    cubit.streetCtrl.clear();
    _setCity(cubit, '');
    setState(() => _filledPhone = null);
  }

  Future<void> _openItemPicker(BuildContext context) async {
    final inventoryCubit = context.read<InventoryCubit>();
    final orderCubit = context.read<OrderCubit>();
    final promotionsCubit = context.read<PromotionsCubit>();
    // Always pull live stock — a stale cache here makes a second order against
    // the same variant fail confusingly at the (correct) atomic transaction.
    // Promotions are re-read too, to default each item's price correctly.
    await Future.wait([
      inventoryCubit.fetchProducts(refresh: true),
      promotionsCubit.load(refresh: true),
    ]);

    if (!context.mounted) return;
    final pick = await showDialog<_PickedItem>(
      context: context,
      builder: (_) => _ItemPickerDialog(
        products: inventoryCubit.products,
        promotions: promotionsCubit.state.promotions,
        remaining: orderCubit.remainingFor,
      ),
    );
    if (pick != null) {
      orderCubit.addItem(
        pick.pickResult,
        pick.quantity,
        unitPrice: pick.unitPrice,
        originalPrice: pick.originalPrice,
        promoId: pick.promotion?.id,
        promoName: pick.promotion?.name,
      );
    }
  }

  Future<void> _pickDeliveryDate(OrderCubit cubit) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
      initialDate: now,
    );
    if (picked != null) {
      setState(() {
        cubit.deliveryDateCtrl.text =
            picked.toIso8601String().split('T').first; // yyyy-MM-dd
      });
    }
  }

  Future<void> _scanQrCode(OrderCubit cubit) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (code != null && code.isNotEmpty) {
      setState(() => cubit.qrCodeCtrl.text = code.split('=').last);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<OrderCubit>();
    final isEditing = cubit.editingOrder != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'تعديل طلب' : 'طلب جديد')),
      body: BlocListener<InventoryCubit, InventoryState>(
        // Live stock changed: trim order lines that now exceed it.
        listenWhen: (_, s) => s is InventoryLoaded,
        listener: (context, state) {
          final warnings = context
              .read<OrderCubit>()
              .reconcileWithStock((state as InventoryLoaded).products);
          if (warnings.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 6),
              content: Text(warnings.join('\n')),
            ));
          }
        },
        child: BlocConsumer<OrderCubit, OrderState>(
        listener: (context, state) {
          if (state is OrderSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
            Navigator.of(context).pop();
          } else if (state is OrderError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
            // Someone else took the stock: reload it so the lines and the
            // picker reflect what is left (the form is kept).
            if (state.isStockShortage) {
              context.read<InventoryCubit>().fetchProducts(refresh: true);
            }
          }
        },
        builder: (context, state) {
          final isSaving = state is OrderLoading;
          return Form(
            key: _formKey,
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
                  child: CustomerPhoneField(
                    controller: cubit.customerPhoneCtrl,
                    onSelected: (c) => _fillFromCustomer(cubit, c),
                  ),
                ),
                if (_filledPhone != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: InputChip(
                        avatar: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('تم تعبئة بيانات العميل'),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        deleteButtonTooltipMessage: 'مسح البيانات المعبأة',
                        onDeleted: () => _clearFilled(cubit),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Labeled(
                  label: 'المحافظة / المدينة',
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_cityFieldVersion),
                    initialValue: _cityChoice,
                    isExpanded: true,
                    menuMaxHeight: 300,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    hint: const Text('اختر المحافظة'),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      for (final g in kJordanGovernorates)
                        DropdownMenuItem(value: g, child: Text(g)),
                      const DropdownMenuItem(
                        value: _kOtherCity,
                        child: Text('أخرى (كتابة يدوية)'),
                      ),
                    ],
                    onTap: () => FocusScope.of(context).unfocus(),
                    onChanged: (v) => setState(() {
                      _cityChoice = v;
                      cubit.addressCtrl.text = v == _kOtherCity
                          ? _customCityCtrl.text.trim()
                          : (v ?? '');
                    }),
                    validator: (v) => v == null ? 'الرجاء اختيار المحافظة' : null,
                  ),
                ),
                if (_cityChoice == _kOtherCity) ...[
                  const SizedBox(height: 12),
                  Labeled(
                    label: 'اكتب المحافظة / المدينة',
                    child: TextFormField(
                      controller: _customCityCtrl,
                      maxLength: 40,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onChanged: (v) => cubit.addressCtrl.text = v.trim(),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'اكتب اسم المحافظة أو المدينة'
                          : null,
                    ),
                  ),
                ],
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
                    readOnly: true,
                    onTap: () => _pickDeliveryDate(cubit),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'اختر التاريخ',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Labeled(
                  label: 'الباركود (اختياري)',
                  child: TextFormField(
                    controller: cubit.qrCodeCtrl,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'اكتب الرمز أو امسحه بالكاميرا',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: 'مسح بالكاميرا',
                        onPressed: () => _scanQrCode(cubit),
                      ),
                    ),
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
                    subtitle: Text(
                      'الكمية: ${item.quantity}'
                      '${item.unitPrice != null ? ' · ${item.unitPrice!.toStringAsFixed(2)} د.أ' : ''}'
                      '${item.promoName != null ? ' · ${item.promoName}' : ''}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => cubit.removeItem(index),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                _OrderValueField(cubit: cubit),
                const SizedBox(height: 12),
                TextFormField(
                  controller: cubit.discountNoteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة خصم (اختياري)',
                    hintText: 'مثال: خصم 5 د.أ أو خصم 10%',
                    border: OutlineInputBorder(),
                  ),
                ),
                // Only offered on new orders; the customer record is written
                // when the order is created, not on later edits.
                if (!isEditing) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('العميل وافق على تلقي العروض'),
                    value: cubit.marketingConsent,
                    onChanged: isSaving ? null : cubit.setMarketingConsent,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          if (_formKey.currentState!.validate()) {
                            cubit.submitOrder();
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('حفظ الطلب'),
                ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }
}

class _PickedItem {
  final PickResult pickResult;
  final int quantity;
  final double unitPrice;
  final double originalPrice;

  /// Set only when the promotion's price was kept unchanged.
  final Promotion? promotion;
  _PickedItem(
    this.pickResult,
    this.quantity, {
    required this.unitPrice,
    required this.originalPrice,
    this.promotion,
  });
}

class _ItemPickerDialog extends StatefulWidget {
  final List<ProductModel> products;
  final List<Promotion> promotions;

  /// Units of a variant that can still be added to this order (live stock
  /// minus what the order's lines already hold).
  final int Function(ProductModel product, String color, String size) remaining;

  const _ItemPickerDialog({
    required this.products,
    required this.promotions,
    required this.remaining,
  });

  @override
  State<_ItemPickerDialog> createState() => _ItemPickerDialogState();
}

class _ItemPickerDialogState extends State<_ItemPickerDialog> {
  ProductModel? _selectedProduct;
  String? _selectedColor;
  String? _selectedSize;
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();

  /// "إظهار المنتجات النافدة": list sold-out products (disabled, "نفد").
  bool _showSoldOut = false;

  /// "المتوفر X فقط" after a typed quantity was clamped.
  String? _qtyNote;

  /// Effective price of [_selectedProduct] now (shared pricing rule).
  EffectivePrice? _pricing;

  int _left(ProductModel p, String color, String size) =>
      widget.remaining(p, color, size);

  /// Sizes of [color] that can still be added, in stored order.
  List<String> _sizesLeft(ProductModel p, String color) => [
        for (final size in (p.stock[color] ?? const <String, int>{}).keys)
          if (_left(p, color, size) > 0) size,
      ];

  List<String> _colorsLeft(ProductModel p) =>
      [for (final c in p.colors) if (_sizesLeft(p, c).isNotEmpty) c];

  bool _addable(ProductModel p) => _colorsLeft(p).isNotEmpty;

  /// Max for the selected variant, or null until one is chosen.
  int? get _max => (_selectedProduct == null ||
          _selectedColor == null ||
          _selectedSize == null)
      ? null
      : _left(_selectedProduct!, _selectedColor!, _selectedSize!);

  void _selectProduct(ProductModel? p) {
    _pricing = p == null
        ? null
        : effectivePrice(
            productId: p.id,
            price: p.price,
            salePrice: p.salePrice,
            promotions: widget.promotions,
            now: DateTime.now(),
          );
    _priceCtrl.text = _pricing?.price.toStringAsFixed(2) ?? '';
  }

  /// Keeps the quantity within 1…[_max]; a clamp shows "المتوفر X فقط".
  void _clampQty() {
    final max = _max;
    if (max == null) return;
    final qty = int.tryParse(normalizeDigits(_qtyCtrl.text.trim()));
    if (qty != null && qty > max) {
      _qtyCtrl.text = '$max';
      _qtyCtrl.selection = TextSelection.collapsed(offset: _qtyCtrl.text.length);
      _qtyNote = 'المتوفر $max فقط';
    } else {
      _qtyNote = null;
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.products.where(_addable).toList();
    final soldOut = widget.products.where((p) => !_addable(p)).toList();
    final product = _selectedProduct;
    final qty = int.tryParse(normalizeDigits(_qtyCtrl.text.trim()));
    final max = _max;
    final qtyValid = qty != null && qty >= 1 && (max == null || qty <= max);

    return AlertDialog(
      title: const Text('اختيار قطعة'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ProductModel>(
                value: _selectedProduct,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'المنتج'),
                items: [
                  for (final p in available)
                    DropdownMenuItem(
                      value: p,
                      child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  if (_showSoldOut)
                    for (final p in soldOut)
                      DropdownMenuItem(
                        value: p,
                        enabled: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Theme.of(context).disabledColor),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('نفد',
                                  style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                            ),
                          ],
                        ),
                      ),
                ],
                onChanged: (value) => setState(() {
                  _selectedProduct = value;
                  _selectedColor = null;
                  _selectedSize = null;
                  _qtyNote = null;
                  _selectProduct(value);
                }),
              ),
              if (available.isEmpty && !_showSoldOut)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('لا توجد منتجات متوفرة حاليًا',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              if (soldOut.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('إظهار المنتجات النافدة'),
                  value: _showSoldOut,
                  onChanged: (v) => setState(() => _showSoldOut = v),
                ),
              if (product != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedColor,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'اللون'),
                  items: [
                    for (final c in _colorsLeft(product))
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedColor = value;
                    _selectedSize = null;
                    _qtyNote = null;
                  }),
                ),
              ],
              if (product != null && _selectedColor != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedSize,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'المقاس'),
                  items: [
                    for (final size in _sizesLeft(product, _selectedColor!))
                      DropdownMenuItem(
                        value: size,
                        child: Builder(builder: (context) {
                          final left = _left(product, _selectedColor!, size);
                          // Amber at the low-stock threshold, like the
                          // products list.
                          final low = left <= product.lowStockThreshold;
                          return Text(
                            '$size (متوفر $left)',
                            style: low
                                ? TextStyle(
                                    color: Colors.amber.shade800,
                                    fontWeight: FontWeight.bold,
                                  )
                                : null,
                          );
                        }),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedSize = value;
                    _clampQty();
                  }),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  ArabicDigitsInputFormatter(),
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setState(_clampQty),
                decoration: InputDecoration(
                  labelText: 'الكمية',
                  helperText: _qtyNote ?? (max != null ? 'الحد الأقصى $max' : null),
                  helperStyle: _qtyNote != null
                      ? TextStyle(color: Colors.orange.shade800)
                      : null,
                ),
              ),
              if (product != null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ArabicDigitsInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'سعر القطعة (د.أ)',
                    helperText: _pricing?.promotion != null
                        ? 'سعر العرض: ${_pricing!.promotion!.name}'
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: product == null ||
                  _selectedColor == null ||
                  _selectedSize == null ||
                  !qtyValid
              ? null
              : () {
                  // Re-check against the order's current lines.
                  final left = _left(product, _selectedColor!, _selectedSize!);
                  if (left <= 0 || qty > left) {
                    setState(() => _qtyNote = left <= 0
                        ? 'هذا المقاس نفد من المخزون'
                        : 'المتوفر $left فقط');
                    return;
                  }
                  final pricing = _pricing!;
                  final entered = double.tryParse(
                      normalizeDigits(_priceCtrl.text.trim())
                          .replaceAll('٫', '.')
                          .replaceAll(',', '.'));
                  final unitPrice = (entered == null || entered < 0)
                      ? pricing.price
                      : roundMoney(entered);
                  Navigator.pop(
                    context,
                    _PickedItem(
                      PickResult(
                        productId: product.id,
                        productName: product.name,
                        color: _selectedColor!,
                        size: _selectedSize!,
                        sku: '${product.id}-$_selectedColor-$_selectedSize',
                      ),
                      qty,
                      unitPrice: unitPrice,
                      originalPrice: product.price,
                      // Edited price → no longer the promotion's price.
                      promotion: unitPrice == pricing.price
                          ? pricing.promotion
                          : null,
                    ),
                  );
                },
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}

/// Arabic decimal separator (٫) and comma → '.'.
class _DecimalSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text.replaceAll('٫', '.').replaceAll(',', '.');
    return t == newValue.text ? newValue : newValue.copyWith(text: t);
  }
}

/// "قيمة الطلب (د.أ)": the order's final total. Follows the items
/// automatically until the owner types in it (manual mode, with a chip and a
/// "إعادة الحساب" reset back to automatic).
class _OrderValueField extends StatelessWidget {
  final OrderCubit cubit;
  const _OrderValueField({required this.cubit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manual = cubit.orderValueManual;
    final required = cubit.hasPricedItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (required)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Expanded(child: Text('المبلغ المحسوب')),
                Text('${cubit.computedOrderValue.toStringAsFixed(2)} د.أ'),
              ],
            ),
          ),
        Labeled(
          label: 'قيمة الطلب (د.أ)',
          child: TextFormField(
            controller: cubit.orderValueCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            inputFormatters: [
              ArabicDigitsInputFormatter(),
              _DecimalSeparatorFormatter(),
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (_) => cubit.onOrderValueEdited(),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              suffixText: 'د.أ',
              suffixIcon: manual
                  ? IconButton(
                      tooltip: 'إعادة الحساب',
                      icon: const Icon(Icons.restart_alt),
                      onPressed: cubit.resetOrderValue,
                    )
                  : null,
            ),
            validator: (v) {
              final text = (v ?? '').trim();
              if (!required && text.isEmpty) return null;
              final value = cubit.enteredOrderValue;
              return (value == null || value <= 0)
                  ? 'أدخل قيمة أكبر من صفر'
                  : null;
            },
          ),
        ),
        if (manual)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: Icon(Icons.edit_outlined,
                      size: 16, color: theme.colorScheme.onSecondaryContainer),
                  label: const Text('تم التعديل يدوياً'),
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
