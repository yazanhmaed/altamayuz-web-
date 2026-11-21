import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../cubit/dashboard/dashboard_cubit.dart';
import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/stocktake/stocktake_cubit.dart';
import '../../cubit/stocktake/stocktake_state.dart';

/// Past stocktakes (`stocktakes/{id}`), newest first, each undoable once.
class StocktakeHistoryScreen extends StatefulWidget {
  const StocktakeHistoryScreen({super.key});

  @override
  State<StocktakeHistoryScreen> createState() => _StocktakeHistoryScreenState();
}

class _StocktakeHistoryScreenState extends State<StocktakeHistoryScreen> {
  @override
  void initState() {
    super.initState();
    context.read<StocktakeCubit>().loadHistory();
  }

  Future<void> _confirmUndo(StocktakeRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تراجع عن هذا الجرد'),
        content: const Text(
          'ستُستعاد الكميات السابقة لكل مقاس غيّره هذا الجرد. '
          'المقاسات التي تغيّرت كميتها بعد الجرد (مثل طلب جديد) سيتم تخطيها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تراجع'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) context.read<StocktakeCubit>().undo(r.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الجرد')),
      body: BlocConsumer<StocktakeCubit, StocktakeState>(
        listener: (context, state) {
          if (state is StocktakeUndoDone) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
            context.read<InventoryCubit>().fetchProducts(refresh: true);
            context.read<DashboardCubit>().loadDashboard();
          } else if (state is StocktakeError) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          final cubit = context.read<StocktakeCubit>();
          if (state is StocktakeHistoryLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (cubit.history.isEmpty) {
            return const Center(child: Text('لا يوجد جرد سابق'));
          }
          return RefreshIndicator(
            onRefresh: cubit.loadHistory,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: cubit.history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = cubit.history[i];
                final busy = cubit.undoingId == r.id;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.fileName.isEmpty ? 'جرد' : r.fileName,
                            style: Theme.of(context).textTheme.titleSmall),
                        if (r.createdAt != null)
                          Text(DateFormat('d MMM yyyy، HH:mm', 'ar')
                              .format(r.createdAt!)),
                        if (r.appliedBy.isNotEmpty)
                          Text('بواسطة: ${r.appliedBy}'),
                        Text(
                            'تم تحديث ${r.updatedSizes} مقاس في ${r.updatedProducts} منتج'
                            '${r.status == 'partial' ? ' (تطبيق جزئي)' : ''}'
                            '${r.status == 'applying' ? ' (لم يكتمل)' : ''}'),
                        if (r.undoneAt != null)
                          Text(
                            'تم التراجع: استعادة ${r.undoRestored}، تخطي ${r.undoSkipped}',
                            style: TextStyle(color: Colors.orange.shade800),
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: OutlinedButton.icon(
                            onPressed:
                                r.undoneAt != null || cubit.undoingId != null
                                    ? null
                                    : () => _confirmUndo(r),
                            icon: busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.undo),
                            label: const Text('تراجع عن هذا الجرد'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
