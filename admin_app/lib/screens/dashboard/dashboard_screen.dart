import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../cubit/dashboard/dashboard_cubit.dart';
import '../../cubit/dashboard/dashboard_state.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DashboardCubit>().loadDashboard();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تسجيل الخروج')),
        ],
      ),
    );
    // The auth gate in main.dart reacts to the sign-out and tears down the
    // signed-in app (cubits included), so no navigation is needed here.
    if (confirmed == true) await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الرئيسية'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          if (state is DashboardLoading || state is DashboardInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DashboardError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: theme.colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'تعذر تحميل البيانات: ${state.message}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () =>
                          context.read<DashboardCubit>().loadDashboard(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = (state as DashboardLoaded).data;

          return RefreshIndicator(
            onRefresh: () => context.read<DashboardCubit>().loadDashboard(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date-range picker: "من"/"إلى" + a reset-to-current-month
                      // chip. Every metric below except the low-stock alert is
                      // scoped to whatever range is currently active.
                      const _DateRangeRow(),
                      const SizedBox(height: 20),

                      // Header title
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'ملخص الفترة المحددة',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Metric Grid (Responsive 4 columns desktop / 2 mobile)
                      GridView.count(
                        crossAxisCount: isDesktop ? 3 : 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: isDesktop ? 1.8 : 1,
                        children: [
                          _MetricCard(
                            icon: Icons.receipt_long_rounded,
                            title: 'إجمالي الطلبات',
                            value: '${data.orderCount}',
                            accentColor: theme.colorScheme.primary,
                          ),
                          _MetricCard(
                            icon: Icons.star_rounded,
                            title: 'الأكثر مبيعًا',
                            value: data.topProductName == null
                                ? 'لا توجد بيانات'
                                : '${data.topProductName} (${data.topProductQty})',
                            accentColor: Colors.amber.shade800,
                          ),
                          _MetricCard(
                            icon: Icons.straighten_rounded,
                            title: 'المقاس الأكثر طلباً',
                            value: data.topSize == null
                                ? 'لا توجد بيانات'
                                : '${data.topSize} (${data.topSizeQty})',
                            accentColor: theme.colorScheme.tertiary,
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // Low Stock Alert Banner Card
                      InkWell(
                        onTap: data.lowStockEntries.isEmpty
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => _LowStockDetailScreen(
                                        entries: data.lowStockEntries),
                                  ),
                                ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: data.lowStockEntries.isEmpty
                                ? theme.colorScheme.surface
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: data.lowStockEntries.isEmpty
                                  ? theme.colorScheme.outlineVariant
                                      .withOpacity(0.5)
                                  : Colors.orange.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: data.lowStockEntries.isEmpty
                                      ? theme
                                          .colorScheme.surfaceContainerHighest
                                      : Colors.orange.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  data.lowStockEntries.isEmpty
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.warning_amber_rounded,
                                  color: data.lowStockEntries.isEmpty
                                      ? Colors.grey
                                      : Colors.orange.shade900,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'حالة المخزون',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      data.lowStockEntries.isEmpty
                                          ? 'المخزون ممتاز، لا يوجد نقص'
                                          : '${data.lowStockEntries.length} مقاس بحاجة لإعادة التجديد',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: data.lowStockEntries.isEmpty
                                            ? theme.colorScheme.onSurface
                                            : Colors.orange.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (data.lowStockEntries.isNotEmpty)
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 16,
                                  color: Colors.orange.shade900,
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Order Source Distribution Card
                      Text(
                        'مصادر الطلبات',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant
                                .withOpacity(0.5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: data.manualOrderCount +
                                      data.storefrontOrderCount ==
                                  0
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('لا توجد بيانات لهذا الشهر'),
                                  ),
                                )
                              : _SourceDistribution(data: data),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DateRangeRow extends StatelessWidget {
  const _DateRangeRow();

  static final _dateFmt = DateFormat('d MMM yyyy', 'ar');
  static final _firstSelectableDate = DateTime(2024);

  Future<void> _pickFrom(BuildContext context, DashboardCubit cubit) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: cubit.currentFrom,
      firstDate: _firstSelectableDate,
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    // Never let "من" land after "إلى" — pull "إلى" forward to match instead
    // of silently querying an inverted range.
    final to = picked.isAfter(cubit.currentTo) ? picked : cubit.currentTo;
    cubit.loadDashboard(from: picked, to: to);
  }

  Future<void> _pickTo(BuildContext context, DashboardCubit cubit) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: cubit.currentTo,
      firstDate: _firstSelectableDate,
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    // Symmetric guard: never let "إلى" land before "من".
    final from =
        picked.isBefore(cubit.currentFrom) ? picked : cubit.currentFrom;
    cubit.loadDashboard(from: from, to: picked);
  }

  Widget _dateField(
    BuildContext context, {
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 160,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(_dateFmt.format(value)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DashboardCubit>();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dateField(
          context,
          label: 'من',
          value: cubit.currentFrom,
          onTap: () => _pickFrom(context, cubit),
        ),
        _dateField(
          context,
          label: 'إلى',
          value: cubit.currentTo,
          onTap: () => _pickTo(context, cubit),
        ),
        ActionChip(
          avatar: const Icon(Icons.today_outlined, size: 16),
          label: const Text('الشهر الحالي'),
          onPressed: cubit.resetToCurrentMonth,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color accentColor;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceDistribution extends StatelessWidget {
  final DashboardData data;
  const _SourceDistribution({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.manualOrderCount + data.storefrontOrderCount;
    final manualFraction = data.manualOrderCount / total;
    final storefrontFraction = data.storefrontOrderCount / total;
    final theme = Theme.of(context);

    Widget bar(
        String label, int count, double fraction, Color color, IconData icon) {
      final percent = (fraction * 100).round();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Text(
                '$count طلب ($percent%)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: color,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar('طلب يدوي', data.manualOrderCount, manualFraction,
            theme.colorScheme.primary, Icons.edit_note_rounded),
        const SizedBox(height: 20),
        bar('المتجر الإلكتروني', data.storefrontOrderCount, storefrontFraction,
            theme.colorScheme.tertiary, Icons.shopping_bag_outlined),
      ],
    );
  }
}

class _LowStockDetailScreen extends StatelessWidget {
  final List<LowStockEntry> entries;
  const _LowStockDetailScreen({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('نقص المخزون'),
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final e = entries[i];
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: Colors.red.shade50,
                child: Icon(Icons.warning_amber_rounded,
                    color: Colors.red.shade700),
              ),
              title: Text(
                e.productName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'اللون: ${e.color}  |  المقاس: ${e.size}',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'المتبقي: ${e.quantity}',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
