import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../cubit/customers/customer_details_cubit.dart';
import '../../cubit/order/order_cubit.dart';
import '../../cubit/order/order_state.dart';
import '../../data/customer/customer_model.dart';
import '../../data/order/order_model.dart';
import '../../utils/relative_date.dart';
import '../orders/widgets/order_card.dart';
import 'customers_screen.dart' show CustomerAvatar, customerBadges;

String _money(double v) => '${v.toStringAsFixed(2)} د.أ';
String _date(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy', 'ar').format(d);

const _orderStatusLabels = {
  OrderStatus.pending: 'معلّق',
  OrderStatus.shipped: 'مشحون',
  OrderStatus.completed: 'مكتمل',
  OrderStatus.returned: 'مرتجع',
};

Color _orderStatusColor(OrderStatus s) => switch (s) {
      OrderStatus.pending => Colors.orange.shade800,
      OrderStatus.shipped => Colors.blue.shade700,
      OrderStatus.completed => Colors.green.shade700,
      OrderStatus.returned => Colors.red.shade700,
    };

class CustomerDetailsScreen extends StatelessWidget {
  final CustomerModel customer;
  const CustomerDetailsScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CustomerDetailsCubit(customer.id, initial: customer)..load(),
      child: const _CustomerDetailsView(),
    );
  }
}

class _CustomerDetailsView extends StatefulWidget {
  const _CustomerDetailsView();

  @override
  State<_CustomerDetailsView> createState() => _CustomerDetailsViewState();
}

class _CustomerDetailsViewState extends State<_CustomerDetailsView> {
  final _notesCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  String? _notesLoadedFor; // the saved notes text the field was last synced to

  @override
  void dispose() {
    _notesCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  /// Syncs the notes field to the stored value, without clobbering text the
  /// owner is still typing.
  void _syncNotes(CustomerModel c) {
    if (_notesLoadedFor == null || _notesCtrl.text == _notesLoadedFor) {
      _notesCtrl.text = c.notes;
    }
    _notesLoadedFor = c.notes;
  }

  Future<void> _launch(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح التطبيق.')));
    }
  }

  void _addTag(CustomerDetailsCubit cubit, String tag) {
    if (tag.trim().isEmpty) return;
    cubit.addTag(tag);
    _tagCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<CustomerDetailsCubit, CustomerDetailsState>(
          listenWhen: (a, b) => b.message != null || a.customer != b.customer,
          listener: (context, state) {
            if (state.customer != null) _syncNotes(state.customer!);
            if (state.message != null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(state.message!)));
            }
          },
        ),
        // Status changes made from an order (opened from this profile) move
        // the customer's stats; re-read them.
        BlocListener<OrderCubit, OrderState>(
          listenWhen: (_, s) => s is OrderSuccess,
          listener: (context, _) {
            context.read<CustomerDetailsCubit>().reloadCustomer();
            setState(() {}); // order objects were updated in place
          },
        ),
      ],
      child: BlocBuilder<CustomerDetailsCubit, CustomerDetailsState>(
        builder: (context, state) {
          final cubit = context.read<CustomerDetailsCubit>();
          final c = state.customer;
          if (c != null && _notesLoadedFor == null) _syncNotes(c);

          return Scaffold(
            appBar: AppBar(
              title: Text(
                c?.name.isNotEmpty == true ? c!.name : 'العميل',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            body: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: Builder(builder: (context) {
                if (c == null && state.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (c == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(state.error ?? 'تعذر تحميل العميل.',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: cubit.load,
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: cubit.load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _header(c),
                      const SizedBox(height: 16),
                      _StatsGrid(customer: c),
                      const SizedBox(height: 16),
                      _consent(c, cubit, state.saving),
                      const SizedBox(height: 16),
                      _notes(cubit, state.saving),
                      const SizedBox(height: 16),
                      _tags(c, cubit, state.saving),
                      const SizedBox(height: 24),
                      _orders(state, cubit),
                    ],
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  Widget _section(String title, Widget child) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _header(CustomerModel c) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final location = [c.city, c.area].where((s) => s.isNotEmpty).join(' - ');
    final badges = customerBadges(c);
    return _section(
      'بيانات العميل',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomerAvatar(name: c.name, radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name.isEmpty ? 'بدون اسم' : c.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(c.phone, textDirection: TextDirection.ltr, style: muted),
                    if (location.isNotEmpty) Text(location, style: muted),
                    if (c.street.isNotEmpty) Text(c.street, style: muted),
                    if (c.lastContactedAt != null)
                      Text('آخر تواصل: ${relativeDateAr(c.lastContactedAt!)}',
                          style: muted),
                  ],
                ),
              ),
            ],
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 4, runSpacing: 4, children: badges),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _launch(Uri(scheme: 'tel', path: c.phone)),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('اتصال'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      _launch(Uri.parse('https://wa.me/${c.whatsappDigits}')),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('واتساب'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _consent(CustomerModel c, CustomerDetailsCubit cubit, bool saving) {
    final on = c.marketingConsent;
    final color = on ? Colors.green.shade700 : Colors.grey.shade700;
    return _section(
      'العروض والتخفيضات',
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    on ? 'موافق على تلقي العروض' : 'غير موافق',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                if (c.consentUpdatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'آخر تحديث: ${_date(c.consentUpdatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: on,
                onChanged: saving ? null : cubit.setConsent,
              ),
              // Quick action for when the customer replies "إيقاف".
              if (on)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                  onPressed: saving ? null : cubit.optOut,
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('طلب إيقاف'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notes(CustomerDetailsCubit cubit, bool saving) {
    return _section(
      'ملاحظات',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _notesCtrl,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'ملاحظات خاصة عن العميل',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              onPressed: saving
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      cubit.saveNotes(_notesCtrl.text);
                    },
              child: const Text('حفظ'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tags(CustomerModel c, CustomerDetailsCubit cubit, bool saving) {
    final suggestions = kSuggestedCustomerTags.where((t) => !c.tags.contains(t));
    return _section(
      'الوسوم',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.tags.isEmpty)
            Text('لا توجد وسوم', style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in c.tags)
                  InputChip(
                    label: Text(t),
                    onDeleted: saving ? null : () => cubit.removeTag(t),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagCtrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) => _addTag(cubit, v),
                  decoration: const InputDecoration(
                    hintText: 'وسم جديد',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'إضافة',
                onPressed: saving ? null : () => _addTag(cubit, _tagCtrl.text),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in suggestions)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(t),
                    onPressed: saving ? null : () => cubit.addTag(t),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _orders(CustomerDetailsState state, CustomerDetailsCubit cubit) {
    final theme = Theme.of(context);
    final children = <Widget>[
      Text('سجل الطلبات',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
    ];
    if (state.ordersLoading) {
      children.add(const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (state.orders.isEmpty && state.ordersError == null) {
      children.add(const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('لا توجد طلبات')),
      ));
    } else {
      for (final o in state.orders) {
        children.add(_OrderTile(order: o, onTap: () => _openOrder(o)));
      }
    }
    if (state.ordersError != null) {
      children.add(Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SelectableText(state.ordersError!, textAlign: TextAlign.center),
            TextButton(
              onPressed: state.orders.isEmpty ? cubit.reloadOrders : cubit.loadMoreOrders,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ));
    } else if (state.ordersLoadingMore) {
      children.add(const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (!state.ordersLoading && state.hasMoreOrders) {
      children.add(Center(
        child: TextButton(
          onPressed: cubit.loadMoreOrders,
          child: const Text('عرض المزيد'),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Future<void> _openOrder(OrderModel order) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _CustomerOrderPage(order: order)),
    );
    if (mounted) setState(() {});
  }
}

class _StatsGrid extends StatelessWidget {
  final CustomerModel customer;
  const _StatsGrid({required this.customer});

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final stats = <(String, String, IconData)>[
      ('عدد الطلبات', '${c.ordersCount}', Icons.receipt_long_outlined),
      ('إجمالي المشتريات', _money(c.deliveredValue), Icons.payments_outlined),
      (
        'متوسط الطلب',
        c.averageOrderValue == null ? '—' : _money(c.averageOrderValue!),
        Icons.analytics_outlined
      ),
      ('المرتجعات', '${c.returnedCount}', Icons.assignment_return_outlined),
      ('أول طلب', _date(c.firstOrderAt), Icons.event_outlined),
      (
        'آخر طلب',
        c.lastOrderAt == null ? '—' : relativeDateAr(c.lastOrderAt!),
        Icons.history
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      const spacing = 8.0;
      final columns = constraints.maxWidth >= 560 ? 3 : 2;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final s in stats) SizedBox(width: width, child: _StatCard(s.$1, s.$2, s.$3)),
        ],
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatCard(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;
  const _OrderTile({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _orderStatusColor(order.status);
    final pieces = order.items.fold<int>(0, (s, i) => s + i.quantity);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('d MMM yyyy — h:mm a', 'ar').format(order.createdAt),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$pieces قطعة'
                      '${order.total != null ? ' · ${_money(order.total!)}' : ''}'
                      '${order.source == 'storefront' ? ' · متجر' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _orderStatusLabels[order.status]!,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const Icon(Icons.chevron_left, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens one order with the app's existing OrderCard, which already carries
/// every order action (item delivered/returned, status, QR, WhatsApp).
class _CustomerOrderPage extends StatelessWidget {
  final OrderModel order;
  const _CustomerOrderPage({required this.order});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      // Rebuilds after each action (OrderCubit updates the order in place).
      // Errors already surface through the orders tab's listener.
      body: BlocBuilder<OrderCubit, OrderState>(
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [OrderCard(order: order)],
        ),
      ),
    );
  }
}
