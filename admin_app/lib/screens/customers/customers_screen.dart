import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/customers/customers_cubit.dart';
import '../../cubit/customers/customers_state.dart';
import '../../data/customer/customer_model.dart';
import '../../utils/arabic_digits.dart';
import '../../utils/relative_date.dart';
import 'customer_details_screen.dart';
import 'offers_screen.dart';

const _sortLabels = {
  CustomerSort.recent: 'الأحدث',
  CustomerSort.mostOrders: 'الأكثر طلبات',
  CustomerSort.topSpend: 'الأكثر إنفاقاً',
};

const _segmentLabels = {
  CustomerSegment.all: 'الكل',
  CustomerSegment.newCustomer: 'جديد',
  CustomerSegment.repeat: 'متكرر',
  CustomerSegment.vip: 'VIP',
  CustomerSegment.inactive: 'خامل',
  CustomerSegment.consent: 'موافقون على العروض',
  CustomerSegment.highReturns: 'مرتجعات عالية',
};

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    context.read<CustomersCubit>().start();
    _scrollCtrl.addListener(() {
      final p = _scrollCtrl.position;
      if (p.pixels >= p.maxScrollExtent - 300) {
        context.read<CustomersCubit>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _openRecompute() async {
    final cubit = context.read<CustomersCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => const _RecomputeDialog(),
    );
    if (phone == null || phone.trim().isEmpty) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('جارٍ إعادة الحساب…')),
    );
    final msg = await cubit.recomputeStats(phone);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openCustomer(CustomerModel c) async {
    final cubit = context.read<CustomersCubit>();
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: c)),
    );
    cubit.refreshOne(c.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Long-press is the hidden maintenance entry point.
        title: GestureDetector(
          onLongPress: _openRecompute,
          child: const Text('العملاء'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final cubit = context.read<CustomersCubit>();
              FocusScope.of(context).unfocus();
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OffersScreen()),
              );
              cubit.refresh(); // picks up new "آخر تواصل" dates
            },
            icon: const Icon(Icons.campaign_outlined),
            label: const Text('إرسال عرض'),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: BlocBuilder<CustomersCubit, CustomersState>(
          builder: (context, state) {
            final cubit = context.read<CustomersCubit>();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    inputFormatters: [ArabicDigitsInputFormatter()],
                    textInputAction: TextInputAction.search,
                    onChanged: cubit.setSearch,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو رقم الهاتف',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: state.search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'مسح',
                              onPressed: () {
                                _searchCtrl.clear();
                                cubit.setSearch('');
                              },
                            ),
                    ),
                  ),
                ),
                if (cubit.isPhoneSearch)
                  const _Hint('البحث بالرقم يعرض كل العملاء المطابقين بدون فرز أو تصنيف.')
                else ...[
                  _ChipsRow(children: [
                    for (final s in CustomerSort.values)
                      ChoiceChip(
                        label: Text(_sortLabels[s]!),
                        selected: state.sort == s,
                        onSelected: (_) => cubit.setSort(s),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  _ChipsRow(children: [
                    for (final s in CustomerSegment.values)
                      FilterChip(
                        label: Text(_segmentLabels[s]!),
                        selected: state.segment == s,
                        showCheckmark: false,
                        onSelected: (_) => cubit.setSegment(s),
                      ),
                  ]),
                  if (cubit.isNameSearch)
                    const _Hint('البحث بالاسم يشمل العملاء المحمّلين فقط؛ مرّر للأسفل لتحميل المزيد.'),
                ],
                const SizedBox(height: 4),
                Expanded(child: _buildList(context, state, cubit)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, CustomersState state, CustomersCubit cubit) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final customers = cubit.visibleCustomers;

    // Error / empty states still sit in a scrollable so pull-to-refresh works.
    Widget scrollableMessage(Widget child) => RefreshIndicator(
          onRefresh: cubit.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [const SizedBox(height: 40), child],
          ),
        );

    if (state.error != null && customers.isEmpty) {
      return scrollableMessage(_ErrorView(message: state.error!, onRetry: cubit.refresh));
    }
    if (customers.isEmpty && !state.hasMore) {
      return scrollableMessage(
        const Column(
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('لا يوجد عملاء هنا', textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: cubit.refresh,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: customers.length + 1,
        itemBuilder: (context, i) {
          if (i < customers.length) {
            final c = customers[i];
            return _CustomerTile(customer: c, onTap: () => _openCustomer(c));
          }
          // Footer: spinner, retry, or a manual "load more" (needed when a
          // name filter leaves too few rows to scroll).
          if (state.loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.error != null) {
            return _ErrorView(message: state.error!, onRetry: cubit.loadMore);
          }
          if (state.hasMore) {
            return Center(
              child: TextButton(
                onPressed: cubit.loadMore,
                child: const Text('تحميل المزيد'),
              ),
            );
          }
          return const SizedBox(height: 8);
        },
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  final List<Widget> children;
  const _ChipsRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final c in children)
            Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: c),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(height: 8),
          // Selectable so a missing-index link can be copied.
          SelectableText(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

/// Small coloured label used for segment/consent badges.
class CustomerBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const CustomerBadge(this.label, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

/// Segment + consent badges for a customer, shared by list and profile.
List<Widget> customerBadges(CustomerModel c) => [
      if (c.isNew) CustomerBadge('جديد', Colors.blue.shade700),
      if (c.isRepeat) CustomerBadge('متكرر', Colors.teal.shade700),
      if (c.isVip) CustomerBadge('VIP', Colors.amber.shade800, icon: Icons.star),
      if (c.isInactive) CustomerBadge('خامل', Colors.grey.shade700),
      if (c.isHighReturns) CustomerBadge('مرتجعات عالية', Colors.red.shade700),
      if (c.marketingConsent)
        CustomerBadge('عروض', Colors.green.shade700, icon: Icons.campaign_outlined),
    ];

class _CustomerTile extends StatelessWidget {
  final CustomerModel customer;
  final VoidCallback onTap;
  const _CustomerTile({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = customer;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomerAvatar(name: c.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name.isEmpty ? 'بدون اسم' : c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.phone,
                      textDirection: TextDirection.ltr,
                      style: muted,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'الطلبات: ${c.ordersCount}'
                      '${c.lastOrderAt != null ? ' · آخر طلب ${relativeDateAr(c.lastOrderAt!)}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                    if (c.lastContactedAt != null)
                      Text(
                        'آخر تواصل ${relativeDateAr(c.lastContactedAt!)}',
                        style: muted,
                      ),
                    if (customerBadges(c).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, runSpacing: 4, children: customerBadges(c)),
                    ],
                  ],
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

class CustomerAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const CustomerAvatar({super.key, required this.name, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _RecomputeDialog extends StatefulWidget {
  const _RecomputeDialog();

  @override
  State<_RecomputeDialog> createState() => _RecomputeDialogState();
}

class _RecomputeDialogState extends State<_RecomputeDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إعادة حساب الإحصائيات'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('يعيد بناء عدّادات عميل واحد من طلباته (للإصلاح فقط).'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            inputFormatters: [ArabicDigitsInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              hintText: '07XXXXXXXX',
              hintTextDirection: TextDirection.ltr,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('إعادة الحساب'),
        ),
      ],
    );
  }
}
