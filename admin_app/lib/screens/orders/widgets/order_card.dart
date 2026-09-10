import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubit/order/order_cubit.dart';
import '../../../data/order/order_model.dart';

String _money(double v) => '${v.toStringAsFixed(2)} د.أ';

/// Order money summary. Nothing for orders with no stored total (older manual
/// orders); a single total line normally; a subtotal / discount / net-total
/// breakdown when a cart-wide quantity discount applied, so the owner can
/// reconcile against what the customer owes on delivery.
class _OrderTotals extends StatelessWidget {
  final OrderModel order;
  const _OrderTotals({required this.order});

  @override
  Widget build(BuildContext context) {
    if (order.total == null && !order.hasCartDiscount) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    if (!order.hasCartDiscount) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(_money(order.total ?? 0),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final subtotal = order.subtotal ?? ((order.total ?? 0) + order.cartDiscountAmount!);
    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
              Text(value,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          line('المجموع الفرعي', _money(subtotal)),
          line(
            'خصم الكمية${order.cartDiscountTierMinQuantity != null ? ' (من ${order.cartDiscountTierMinQuantity} قطع)' : ''}',
            '-${_money(order.cartDiscountAmount!)}',
          ),
          const Divider(height: 12),
          line('الإجمالي المستحق', _money(order.total ?? 0), bold: true),
          Text('* تطبّق خصم كمية على هذا الطلب',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ],
      ),
    );
  }
}

class OrderCard extends StatelessWidget {
  final OrderModel order;
  const OrderCard({super.key, required this.order});

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.shipped:
        return Colors.blue;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.returned:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OrderCubit>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (order.source == 'storefront')
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCE6E5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storefront_outlined, size: 13, color: Color(0xFF1F3A3D)),
                    SizedBox(width: 4),
                    Text('من المتجر', style: TextStyle(fontSize: 11, color: Color(0xFF1F3A3D))),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(order.customerName, style: Theme.of(context).textTheme.titleMedium),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.status.englishName,
                    style: TextStyle(color: _statusColor(order.status), fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(order.customerPhone),
            Text('${order.address} - ${order.area}'),
            if (order.street.isNotEmpty) Text(order.street),
            const Divider(),
            _OrderItemsList(order: order, cubit: cubit),
            _OrderTotals(order: order),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (order.status != OrderStatus.completed)
                  for (final status in OrderStatus.values)
                    if (status != order.status)
                      OutlinedButton(
                        onPressed: () => cubit.updateOrderStatus(order: order, newStatus: status),
                        child: Text('تعيين: ${status.englishName}'),
                      ),
                OutlinedButton.icon(
                  onPressed: () => cubit.updateOrderQrCode(order: order, context: context),
                  icon: const Icon(Icons.qr_code_scanner, size: 16),
                  label: const Text('مسح QR'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Color _itemStatusColor(ItemStatus status) {
  switch (status) {
    case ItemStatus.pending:
      return Colors.orange;
    case ItemStatus.delivered:
      return Colors.green;
    case ItemStatus.returned:
      return Colors.red;
  }
}

/// Per-item rows with "تسليم"/"إرجاع" actions. Tracks in-flight item ids so a
/// rapid double-tap can't fire two `updateItemStatus` calls for the same item
/// before the first resolves. This is UX polish only — the real double-restock
/// guard is the live re-check inside `updateItemStatus`'s transaction (this set
/// resets on reload and does nothing across tabs/devices).
class _OrderItemsList extends StatefulWidget {
  final OrderModel order;
  final OrderCubit cubit;
  const _OrderItemsList({required this.order, required this.cubit});

  @override
  State<_OrderItemsList> createState() => _OrderItemsListState();
}

class _OrderItemsListState extends State<_OrderItemsList> {
  final Set<String> _pendingItemIds = {};

  Future<void> _update(String itemId, ItemStatus newStatus) async {
    if (_pendingItemIds.contains(itemId)) return;
    setState(() => _pendingItemIds.add(itemId));
    try {
      await widget.cubit.updateItemStatus(
        order: widget.order,
        itemId: itemId,
        newStatus: newStatus,
      );
    } finally {
      if (mounted) setState(() => _pendingItemIds.remove(itemId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in widget.order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.productName ?? item.productId} — ${item.color} — مقاس ${item.size} × ${item.quantity}',
                  ),
                ),
                if (item.status == ItemStatus.pending) ...[
                  TextButton(
                    onPressed: _pendingItemIds.contains(item.itemId)
                        ? null
                        : () => _update(item.itemId, ItemStatus.delivered),
                    child: const Text('تسليم'),
                  ),
                  TextButton(
                    onPressed: _pendingItemIds.contains(item.itemId)
                        ? null
                        : () => _update(item.itemId, ItemStatus.returned),
                    child: const Text('إرجاع'),
                  ),
                ] else
                  Text(
                    item.status.englishName,
                    style: TextStyle(
                      color: _itemStatusColor(item.status),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
