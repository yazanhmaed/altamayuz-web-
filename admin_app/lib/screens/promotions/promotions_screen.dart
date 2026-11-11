import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../cubit/promotions/promotions_cubit.dart';
import '../../utils/promotion_pricing.dart';
import 'promotion_form_screen.dart';

String formatPromoDate(DateTime d) =>
    DateFormat('d MMM yyyy، HH:mm', 'ar').format(d.toLocal());

Color promotionStatusColor(PromotionStatus s) => switch (s) {
      PromotionStatus.running => Colors.green.shade700,
      PromotionStatus.scheduled => Colors.blue.shade700,
      PromotionStatus.paused => Colors.orange.shade800,
      PromotionStatus.ended => Colors.grey.shade700,
    };

/// "العروض": product-group percentage promotions with start/end dates.
class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  /// null = all statuses.
  PromotionStatus? _filter;

  @override
  void initState() {
    super.initState();
    context.read<PromotionsCubit>().load();
  }

  Future<void> _openForm({Promotion? editing}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PromotionFormScreen(editing: editing),
    ));
  }

  Future<void> _confirmDelete(Promotion p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العرض'),
        content: Text('هل تريد حذف العرض "${p.name}"؟ لا يمكن التراجع عن ذلك.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<PromotionsCubit>().delete(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('العروض'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<PromotionsCubit>().load(refresh: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('عرض جديد'),
      ),
      body: BlocConsumer<PromotionsCubit, PromotionsState>(
        listenWhen: (_, s) => s.message != null,
        listener: (context, s) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.message!))),
        builder: (context, state) {
          if (state.loading && state.promotions.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null && state.promotions.isEmpty) {
            return _CenteredMessage(
              icon: Icons.error_outline,
              text: state.error!,
              action: OutlinedButton.icon(
                onPressed: () =>
                    context.read<PromotionsCubit>().load(refresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            );
          }

          final now = DateTime.now();
          final list = state.promotions
              .where((p) => _filter == null || p.statusAt(now) == _filter)
              .toList();

          return Column(
            children: [
              if (state.busy) const LinearProgressIndicator(minHeight: 2),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    _chip('الكل', null),
                    for (final s in const [
                      PromotionStatus.running,
                      PromotionStatus.scheduled,
                      PromotionStatus.paused,
                      PromotionStatus.ended,
                    ])
                      _chip(s.label, s),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? _CenteredMessage(
                        icon: Icons.local_offer_outlined,
                        text: state.promotions.isEmpty
                            ? 'لا توجد عروض بعد. أنشئ أول عرض.'
                            : 'لا توجد عروض بهذه الحالة.',
                      )
                    : RefreshIndicator(
                        onRefresh: () =>
                            context.read<PromotionsCubit>().load(refresh: true),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) => _PromotionTile(
                            promotion: list[i],
                            now: now,
                            busy: state.busy,
                            onEdit: () => _openForm(editing: list[i]),
                            onDelete: () => _confirmDelete(list[i]),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, PromotionStatus? status) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == status,
        onSelected: (_) => setState(() => _filter = status),
      ),
    );
  }
}

enum _Action { edit, toggle, duplicate, delete }

class _PromotionTile extends StatelessWidget {
  final Promotion promotion;
  final DateTime now;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PromotionTile({
    required this.promotion,
    required this.now,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = promotion;
    final status = p.statusAt(now);
    final color = promotionStatusColor(status);
    final cubit = context.read<PromotionsCubit>();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.label,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          p.discountLabel,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p.productIds.length} منتج',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'من ${formatPromoDate(p.startAt)}\nإلى ${formatPromoDate(p.endAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_Action>(
                enabled: !busy,
                onSelected: (a) {
                  switch (a) {
                    case _Action.edit:
                      onEdit();
                    case _Action.toggle:
                      cubit.setActive(p, !p.isActive);
                    case _Action.duplicate:
                      cubit.duplicate(p);
                    case _Action.delete:
                      onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: _Action.edit, child: Text('تعديل')),
                  PopupMenuItem(
                    value: _Action.toggle,
                    child: Text(p.isActive ? 'إيقاف' : 'استئناف'),
                  ),
                  const PopupMenuItem(
                      value: _Action.duplicate, child: Text('نسخ العرض')),
                  PopupMenuItem(
                    value: _Action.delete,
                    child: Text('حذف',
                        style: TextStyle(color: Colors.red.shade700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _CenteredMessage({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
