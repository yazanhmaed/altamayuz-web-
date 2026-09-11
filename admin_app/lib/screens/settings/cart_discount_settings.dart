import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/arabic_digits.dart';

/// Owner-facing editor for `settings/cartDiscountTiers` — the cart-wide
/// quantity-discount tiers applied at storefront checkout.
///
/// Client-side validation here is a convenience for the owner; it is NOT the
/// authority. `submitPublicOrder` independently re-sanitizes every tier on
/// every order (discards minQuantity < 2, out-of-range percentages, non-positive
/// fixed amounts) and re-sorts them, so a bad save can never produce a wrong
/// charge.
class CartDiscountSettingsScreen extends StatefulWidget {
  const CartDiscountSettingsScreen({super.key});

  @override
  State<CartDiscountSettingsScreen> createState() =>
      _CartDiscountSettingsScreenState();
}

class _CartDiscountSettingsScreenState
    extends State<CartDiscountSettingsScreen> {
  static final _doc = FirebaseFirestore.instance
      .collection('settings')
      .doc('cartDiscountTiers');

  final List<_TierDraft> _tiers = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final t in _tiers) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await _doc.get();
      final raw = snap.data()?['tiers'];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is! Map) continue;
          _tiers.add(_TierDraft.fromMap(Map<String, dynamic>.from(entry)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر تحميل الإعدادات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addTier() {
    setState(() => _tiers.add(_TierDraft.empty()));
  }

  void _removeTier(int index) {
    setState(() => _tiers.removeAt(index).dispose());
  }

  /// Returns an error message, or null when every row is valid.
  String? _validate() {
    final mins = <int>{};
    for (var i = 0; i < _tiers.length; i++) {
      final t = _tiers[i];
      final min = int.tryParse(normalizeDigits(t.minCtrl.text.trim()));
      if (min == null || min < 2) {
        return 'الحد الأدنى للكمية في الشريحة ${i + 1} يجب أن يكون رقمًا صحيحًا ≥ 2.';
      }
      if (!mins.add(min)) {
        return 'لا يمكن تكرار نفس الحد الأدنى للكمية ($min) في أكثر من شريحة.';
      }
      final value = double.tryParse(normalizeDigits(t.valueCtrl.text.trim()));
      if (value == null) {
        return 'قيمة الخصم في الشريحة ${i + 1} غير صالحة.';
      }
      if (t.type == 'percentage' && (value < 1 || value > 100)) {
        return 'نسبة الخصم في الشريحة ${i + 1} يجب أن تكون بين 1 و 100.';
      }
      if (t.type == 'fixed' && value <= 0) {
        return 'قيمة الخصم الثابت في الشريحة ${i + 1} يجب أن تكون أكبر من صفر.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final tiers = _tiers
        .map((t) => {
              'minQuantity': int.parse(normalizeDigits(t.minCtrl.text.trim())),
              'type': t.type,
              'value': double.parse(normalizeDigits(t.valueCtrl.text.trim())),
            })
        .toList()
      ..sort((a, b) =>
          (a['minQuantity'] as int).compareTo(b['minQuantity'] as int));

    setState(() => _saving = true);
    try {
      await _doc.set({'tiers': tiers}, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حفظ شرائح الخصم.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّر الحفظ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خصومات الكمية')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'يُطبَّق خصم واحد فقط على السلة كاملةً: أعلى شريحة يبلغها '
                  'إجمالي عدد القطع. الشرائح لا تتجمّع.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (_tiers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('لا توجد شرائح — لن يُطبَّق أي خصم كمية.'),
                    ),
                  ),
                for (var i = 0; i < _tiers.length; i++)
                  _TierRow(
                    key: ObjectKey(_tiers[i]),
                    index: i,
                    draft: _tiers[i],
                    onTypeChanged: (v) => setState(() => _tiers[i].type = v),
                    onRemove: () => _removeTier(i),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addTier,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة شريحة'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('حفظ'),
                ),
              ],
            ),
    );
  }
}

class _TierDraft {
  final TextEditingController minCtrl;
  final TextEditingController valueCtrl;
  String type; // 'percentage' | 'fixed'

  _TierDraft({required this.minCtrl, required this.valueCtrl, required this.type});

  factory _TierDraft.empty() => _TierDraft(
        minCtrl: TextEditingController(),
        valueCtrl: TextEditingController(),
        type: 'percentage',
      );

  factory _TierDraft.fromMap(Map<String, dynamic> map) {
    final type = map['type'] == 'fixed' ? 'fixed' : 'percentage';
    final min = (map['minQuantity'] as num?)?.toInt();
    final value = (map['value'] as num?)?.toDouble();
    return _TierDraft(
      minCtrl: TextEditingController(text: min?.toString() ?? ''),
      valueCtrl: TextEditingController(
        text: value == null
            ? ''
            : (value == value.roundToDouble()
                ? value.toStringAsFixed(0)
                : value.toString()),
      ),
      type: type,
    );
  }

  void dispose() {
    minCtrl.dispose();
    valueCtrl.dispose();
  }
}

class _TierRow extends StatelessWidget {
  final int index;
  final _TierDraft draft;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onRemove;

  const _TierRow({
    super.key,
    required this.index,
    required this.draft,
    required this.onTypeChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('شريحة ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
            TextField(
              controller: draft.minCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                ArabicDigitsInputFormatter(),
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'الحد الأدنى لعدد القطع (≥ 2)',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: draft.type,
                    decoration: const InputDecoration(labelText: 'نوع الخصم'),
                    items: const [
                      DropdownMenuItem(
                          value: 'percentage', child: Text('نسبة %')),
                      DropdownMenuItem(
                          value: 'fixed', child: Text('مبلغ ثابت (د.أ)')),
                    ],
                    onChanged: (v) => onTypeChanged(v ?? 'percentage'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: draft.valueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [ArabicDigitsInputFormatter()],
                    decoration: InputDecoration(
                      labelText: draft.type == 'percentage'
                          ? 'النسبة (1–100)'
                          : 'المبلغ (> 0)',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
