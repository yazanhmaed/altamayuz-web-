import 'dart:developer';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../cart/cart_controller.dart';
import '../data/cart_discount_repository.dart';
import '../models/cart_discount.dart';
import '../utils/jordan_phone.dart';
import '../utils/responsive.dart';
import 'order_success_page.dart';

class CheckoutPage extends StatefulWidget {
  final CartLine? buyNowItem;
  const CheckoutPage({super.key, this.buyNowItem});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  bool _submitting = false;

  /// Cart-wide quantity-discount tiers, read once on load. Empty until the
  /// one-time Firestore read completes, and empty forever if none are
  /// configured — either way `_discount` then resolves to "no discount".
  List<CartDiscountTier> _tiers = const [];

  List<CartLine> get _items =>
      widget.buyNowItem != null ? [widget.buyNowItem!] : cartController.value;

  double get _total => _items.fold(0.0, (sum, l) => sum + l.lineTotal);

  int get _totalQuantity => _items.fold(0, (sum, l) => sum + l.quantity);

  /// The single cart-wide discount that applies (highest qualifying tier), or
  /// a zero result. Display only — the server recomputes this authoritatively.
  CartDiscountResult get _discount => computeCartDiscount(
        tiers: _tiers,
        totalQuantity: _totalQuantity,
        subtotal: _total,
      );

  @override
  void initState() {
    super.initState();
    loadCartDiscountTiers().then((tiers) {
      if (mounted) setState(() => _tiers = tiers);
    }).catchError((_) {
      // Network hiccup reading config — proceed with no cart discount rather
      // than blocking checkout. The server still applies any real discount.
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _areaCtrl.dispose();
    _streetCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('submitPublicOrder');
      await callable.call({
        'customerName': _nameCtrl.text.trim(),
        'customerPhone': jordanPhoneToE164(_phoneCtrl.text),
        'address': _cityCtrl.text.trim(),
        'area': _areaCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'items': _items
            .map((l) => {
                  'productId': l.product.id,
                  'color': l.variant.color,
                  'size': l.size,
                  'quantity': l.quantity,
                })
            .toList(),
      });

      if (widget.buyNowItem == null) {
        cartController.clear();
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OrderSuccessPage()),
        (route) => route.isFirst,
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'حدث خطأ، حاول مرة أخرى.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      log(e.message ?? '');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('حدث خطأ، حاول مرة أخرى.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          // ignore: deprecated_member_use
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_bag_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'ملخص الطلب',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Chip(
                label: Text('${_items.length} منتجات'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.primary,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Items List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final line = _items[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${line.variant.color} | مقاس ${line.size} × ${line.quantity}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${line.lineTotal.toStringAsFixed(0)} د.أ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Pricing Breakdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'رسوم الشحن',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Text(
                'مجاني',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // Cart-wide quantity discount — shown only when one actually applies
          // (no empty row / gap otherwise).
          if (_discount.amount > 0) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'خصم الكمية',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                Text(
                  '-${_discount.amount.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الإجمالي النهائي',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${(_total - _discount.amount).toStringAsFixed(2)} د.أ',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'معلومات التوصيل',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Name Field
          TextFormField(
            controller: _nameCtrl,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              labelText: 'الاسم الكامل',
              prefixIcon: const Icon(Icons.person_outline),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
          ),
          const SizedBox(height: 16),

          // Phone Field — fixed Jordan country code, bare 9-digit number.
          // A leading 0 (e.g. 077…) is stripped automatically as you type.
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            inputFormatters: [JordanPhoneInputFormatter()],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              labelText: 'رقم الهاتف',
              hintText: '7XXXXXXXX',
              hintTextDirection: TextDirection.ltr,
              prefixIcon: const Padding(
                padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: 1,
                  child: Text(
                    '🇯🇴 $jordanDialCode',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) =>
                (v == null || v.trim().length != jordanLocalNumberLength)
                    ? 'أدخل رقمًا من 9 أرقام'
                    : null,
          ),
          const SizedBox(height: 16),

          // City & Area Fields (Side by Side on Desktop/Tablet, Vertical on Mobile)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 450;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                children: [
                  Expanded(
                    flex: isWide ? 1 : 0,
                    child: TextFormField(
                      controller: _cityCtrl,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: InputDecoration(
                        labelText: 'المدينة',
                        prefixIcon: const Icon(Icons.location_city_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                  ),
                  SizedBox(
                    width: isWide ? 12 : 0,
                    height: isWide ? 0 : 16,
                  ),
                  Expanded(
                    flex: isWide ? 1 : 0,
                    child: TextFormField(
                      controller: _areaCtrl,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: InputDecoration(
                        labelText: 'المنطقة / الحي',
                        prefixIcon: const Icon(Icons.map_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Street Details
          TextFormField(
            controller: _streetCtrl,
            decoration: InputDecoration(
              labelText: 'تفاصيل العنوان / الشارع (اختياري)',
              prefixIcon: const Icon(Icons.home_outlined),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),

          // Informational Badges
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: theme.colorScheme.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                // ignore: deprecated_member_use
                color: theme.colorScheme.primary.withOpacity(0.15),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.payments_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'الدفع عند استلام الطلب',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Icon(Icons.assignment_return_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'في حال الإرجاع، يتم دفع بدل توصيل (دينارين فقط)',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'تأكيد الطلب الآن',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إتمام الطلب'),
        centerTitle: true,
      ),
      body: ResponsiveCenter(
        maxWidth: 1000,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (isDesktop) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildForm(context),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      flex: 2,
                      child: StickySummary(child: _buildSummary(context)),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  _buildSummary(context),
                  const SizedBox(height: 32),
                  _buildForm(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Helper to keep the summary visible when scrolling on Desktop
class StickySummary extends StatelessWidget {
  final Widget child;
  const StickySummary({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [child],
    );
  }
}
