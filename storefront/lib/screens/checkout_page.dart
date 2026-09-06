import 'dart:developer';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../cart/cart_controller.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'order_success_page.dart';

class CheckoutPage extends StatefulWidget {
  /// When set, checkout is a "buy now" purchase of this single item only —
  /// the shared cart is neither read from nor modified. When null (the
  /// normal "continue to checkout" flow), checkout reads and submits the
  /// shared cart's contents as before.
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

  /// Single source of truth for the order summary, total, and submission
  /// payload — a "buy now" purchase of one item, or the shared cart.
  List<CartLine> get _items =>
      widget.buyNowItem != null ? [widget.buyNowItem!] : cartController.value;

  double get _total => _items.fold(0.0, (sum, l) => sum + l.lineTotal);

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
      // Both the cart flow and "buy now" submit through the SAME callable,
      // which validates stock and deducts it atomically in one transaction.
      // The storefront never writes the order document or touches `products`
      // directly — it only sends what was ordered.
      final callable =
          FirebaseFunctions.instance.httpsCallable('submitPublicOrder');
      await callable.call({
        'customerName': _nameCtrl.text.trim(),
        'customerPhone': _phoneCtrl.text.trim(),
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
      // Only the shared cart's own checkout flow clears it — a "buy now"
      // purchase never touches the cart, since it wasn't its source.
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
      // The function reports the specific product/color/size that ran out
      // in `message`; show it verbatim so the customer knows what failed.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'حدث خطأ، حاول مرة أخرى.')),
      );
      log(e.message ?? '');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ، حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildSummary(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ملخص الطلب', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ..._items.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(
                            '${l.product.name} — ${l.variant.color} — مقاس ${l.size} × ${l.quantity}')),
                    Text('${l.lineTotal.toStringAsFixed(0)} د.أ'),
                  ],
                ),
              ),
            ),
            const Divider(),
            Row(
              children: [
                const Text('الإجمالي',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${_total.toStringAsFixed(0)} د.أ',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.accent)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameCtrl,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
                labelText: 'الاسم الكامل', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
                labelText: 'رقم الهاتف', border: OutlineInputBorder()),
            validator: (v) =>
                (v == null || v.trim().length < 9) ? 'الرقم غير مكتمل' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cityCtrl,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
                labelText: 'المدينة', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _areaCtrl,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
                labelText: 'المنطقة', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _streetCtrl,
            decoration: const InputDecoration(
                labelText: 'تفاصيل العنوان (اختياري)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.local_shipping_outlined, color: AppColors.accent),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'الدفع كاش عند استلام الطلب — لا حاجة للدفع أونلاين.')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('تأكيد الطلب'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إتمام الطلب')),
      body: ResponsiveCenter(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= Responsive.tabletMax) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 3,
                        child:
                            SingleChildScrollView(child: _buildForm(context))),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: _buildSummary(context)),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSummary(context),
                const SizedBox(height: 20),
                _buildForm(context)
              ],
            );
          },
        ),
      ),
    );
  }
}
