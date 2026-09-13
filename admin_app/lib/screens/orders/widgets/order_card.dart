import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../cubit/order/order_cubit.dart';
import '../../../data/order/order_model.dart';

String _money(double v) => '${v.toStringAsFixed(2)} د.أ';

String _buildWhatsAppConfirmationUrl(OrderModel order) {
  final digitsOnly = order.customerPhone.replaceAll(RegExp(r'[^0-9]'), '');

  final buffer = StringBuffer()
    ..writeln('مرحباً ${order.customerName} 👋')
    ..writeln('نود تأكيد طلبك:')
    ..writeln();
  for (final item in order.items) {
    buffer.writeln(
      '- ${item.productName ?? item.productId} — ${item.color} — مقاس ${item.size} × ${item.quantity}',
    );
  }
  buffer
    ..writeln()
    ..writeln('📍 العنوان: ${order.address} - ${order.area}');
  if (order.street.isNotEmpty) buffer.writeln(order.street);
  if (order.discountNote.isNotEmpty) buffer.writeln('🏷️ ${order.discountNote}');
  if (order.total != null) {
    buffer.writeln('💰 الإجمالي: ${order.total!.toStringAsFixed(2)} د.أ');
  }
  buffer.writeln();
  buffer.write('الرجاء تأكيد الطلب بالرد على هذه الرسالة 🙏');

  final encodedMessage = Uri.encodeComponent(buffer.toString());
  return 'https://wa.me/$digitsOnly?text=$encodedMessage';
}

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
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'الإجمالي النهائي',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              _money(order.total ?? 0),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    final subtotal = order.subtotal ?? ((order.total ?? 0) + order.cartDiscountAmount!);
    Widget line(String label, String value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: color,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          line('المجموع الفرعي', _money(subtotal)),
          line(
            'خصم الكمية${order.cartDiscountTierMinQuantity != null ? ' (${order.cartDiscountTierMinQuantity} قطع+)' : ''}',
            '-${_money(order.cartDiscountAmount!)}',
            color: Colors.green.shade700,
          ),
          const Divider(height: 12),
          line('الإجمالي المستحق', _money(order.total ?? 0), bold: true),
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
        return Colors.orange.shade800;
      case OrderStatus.shipped:
        return Colors.blue.shade700;
      case OrderStatus.completed:
        return Colors.green.shade700;
      case OrderStatus.returned:
        return Colors.red.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<OrderCubit>();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header: Source Badge & Current Main Status Badge
            Row(
              children: [
                if (order.source == 'storefront')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storefront_outlined,
                            size: 14, color: theme.colorScheme.onPrimaryContainer),
                        const SizedBox(width: 4),
                        Text(
                          'طلب متجر',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor(order.status).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 4,
                        backgroundColor: _statusColor(order.status),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'الحالة: ${order.status.englishName}',
                        style: TextStyle(
                          color: _statusColor(order.status),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. Customer Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  child: Icon(Icons.person_outline, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('d MMM yyyy — h:mm a', 'ar').format(order.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined,
                              size: 14, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            order.customerPhone,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 14, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${order.address} - ${order.area}${order.street.isNotEmpty ? ' (${order.street})' : ''}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),

            // 3. Items & Totals
            _OrderItemsList(order: order, cubit: cubit),
            _OrderTotals(order: order),
            if (order.discountNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'ملاحظة: ${order.discountNote}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),

            // 4. Quick Action Buttons (WhatsApp & QR)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      final uri = Uri.parse(_buildWhatsAppConfirmationUrl(order));
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تعذر فتح واتساب.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('تأكيد عبر واتساب'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => cubit.updateOrderQrCode(order: order, context: context),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('QR'),
                ),
              ],
            ),

            // 5. Explicit Order Status Switch Panel (Removes confusion)
            if (order.status != OrderStatus.completed) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تغيير حالة الطلب العامة:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final status in OrderStatus.values)
                          if (status != order.status)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: _statusColor(status),
                                side: BorderSide(
                                  color: _statusColor(status).withOpacity(0.5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => cubit.updateOrderStatus(
                                  order: order, newStatus: status),
                              icon: const Icon(Icons.sync_alt, size: 14),
                              label: Text('تحويل إلى: ${status.englishName}'),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color _itemStatusColor(ItemStatus status) {
  switch (status) {
    case ItemStatus.pending:
      return Colors.orange.shade800;
    case ItemStatus.delivered:
      return Colors.green.shade700;
    case ItemStatus.returned:
      return Colors.red.shade700;
  }
}

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
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'محتويات الطلب',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in widget.order.items)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.productName ?? item.productId} — ${item.color} (مقاس ${item.size}) × ${item.quantity}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                if (item.status == ItemStatus.pending) ...[
                  InkWell(
                    onTap: _pendingItemIds.contains(item.itemId)
                        ? null
                        : () => _update(item.itemId, ItemStatus.delivered),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Text(
                        'تسليم',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _pendingItemIds.contains(item.itemId)
                        ? null
                        : () => _update(item.itemId, ItemStatus.returned),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Text(
                        'إرجاع',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _itemStatusColor(item.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.status.englishName,
                      style: TextStyle(
                        color: _itemStatusColor(item.status),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}