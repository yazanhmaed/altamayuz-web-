import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/dashboard/dashboard_cubit.dart';
import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/inventory/inventory_state.dart';
import '../../utils/arabic_digits.dart';
import '../../widgets/product_image.dart';

const _maxRestockQty = 10000;

/// Opens the quick-restock dialog for one low-stock [entry]. On success the
/// dashboard's low-stock list is updated locally and a SnackBar confirms it.
Future<void> showQuickRestockDialog(BuildContext context, LowStockEntry entry) async {
  final added = await showDialog<int>(
    context: context,
    builder: (_) => _QuickRestockDialog(entry: entry),
  );
  if (added == null || !context.mounted) return;
  // The products tab (kept alive in the home IndexedStack) also reacts to
  // the inventory cubit's generic success message — replace it with ours.
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text('تمت إضافة $added قطعة إلى المقاس ${entry.size} (${entry.color})'),
    ));
}

class _QuickRestockDialog extends StatefulWidget {
  final LowStockEntry entry;
  const _QuickRestockDialog({required this.entry});

  @override
  State<_QuickRestockDialog> createState() => _QuickRestockDialogState();
}

class _QuickRestockDialogState extends State<_QuickRestockDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _qtyCtrl.text.length);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  int? get _qty => int.tryParse(normalizeDigits(_qtyCtrl.text.trim()));

  String? get _qtyError {
    final q = _qty;
    if (q == null || q < 1) return 'أدخل عددًا صحيحًا من 1 فأكثر';
    if (q > _maxRestockQty) return 'الحد الأقصى $_maxRestockQty';
    return null;
  }

  void _setQty(int value) {
    final clamped = value.clamp(1, _maxRestockQty);
    _qtyCtrl.text = '$clamped';
    _qtyCtrl.selection = TextSelection.collapsed(offset: _qtyCtrl.text.length);
    setState(() => _saveError = null);
  }

  Future<void> _submit() async {
    if (_saving || _qtyError != null) return;
    final qty = _qty!;
    final e = widget.entry;
    final inventory = context.read<InventoryCubit>();
    final dashboard = context.read<DashboardCubit>();
    setState(() {
      _saving = true;
      _saveError = null;
    });

    await inventory.addStockQuantities(
      productId: e.productId,
      additions: {
        e.color: {e.size: qty},
      },
    );
    if (!mounted) return;

    final state = inventory.state;
    if (state is! InventorySuccess) {
      ScaffoldMessenger.of(context).clearSnackBars();
      setState(() {
        _saving = false;
        _saveError = state is InventoryError ? state.message : 'تعذّرت إضافة الكمية.';
      });
      return;
    }

    // addStockQuantities re-reads the product after the increment, so take
    // the server's quantity (which includes any concurrent change).
    int newQty = e.quantity + qty;
    for (final p in inventory.products) {
      if (p.id == e.productId) {
        newQty = p.stock[e.color]?[e.size] ?? newQty;
        break;
      }
    }
    dashboard.applyRestock(
      productId: e.productId,
      color: e.color,
      size: e.size,
      newQuantity: newQty,
    );
    Navigator.of(context).pop(qty);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = widget.entry;
    final qtyError = _qtyError;
    final preview = e.quantity + (qtyError == null ? _qty! : 0);

    final Color currentColor = e.quantity <= 0
        ? Colors.red.shade800
        : e.quantity == 1
            ? Colors.amber.shade900
            : scheme.onSurface;

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 44,
                height: 44,
                child: ProductImage(url: e.imageUrl, cacheWidth: 132, placeholderIconSize: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                e.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _InfoChip(label: 'اللون: ${e.color}'),
                  _InfoChip(label: 'المقاس: ${e.size}'),
                ],
              ),
              const SizedBox(height: 14),
              Text.rich(
                TextSpan(
                  text: 'الكمية الحالية: ',
                  children: [
                    TextSpan(
                      text: '${e.quantity}',
                      style: TextStyle(color: currentColor, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton.outlined(
                    tooltip: 'إنقاص',
                    onPressed: _saving || (_qty ?? 1) <= 1 ? null : () => _setQty((_qty ?? 1) - 1),
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      autofocus: true,
                      enabled: !_saving,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        ArabicDigitsInputFormatter(),
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        labelText: 'الكمية المضافة',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: qtyError,
                        errorMaxLines: 2,
                      ),
                      onChanged: (_) => setState(() => _saveError = null),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'زيادة',
                    onPressed: _saving || (_qty ?? 0) >= _maxRestockQty
                        ? null
                        : () => _setQty((_qty ?? 0) + 1),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final n in const [5, 10, 20])
                    ActionChip(
                      label: Text('+$n'),
                      onPressed: _saving ? null : () => _setQty(n),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'الكمية بعد الإضافة: $preview',
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (_saveError != null) ...[
                const SizedBox(height: 10),
                Text(
                  'تعذّرت إضافة الكمية: $_saveError',
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _saving || qtyError != null ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('إضافة'),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}
