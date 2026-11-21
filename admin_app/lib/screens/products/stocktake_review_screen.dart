import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../cubit/dashboard/dashboard_cubit.dart';
import '../../cubit/inventory/inventory_cubit.dart';
import '../../cubit/stocktake/stocktake_cubit.dart';
import '../../cubit/stocktake/stocktake_state.dart';
import '../../utils/stocktake_matching.dart';
import 'add_product.dart';

String _dateTime(DateTime d) =>
    DateFormat('d MMM yyyy، HH:mm', 'ar').format(d.toLocal());

enum _Filter { all, changed, review }

/// Diff of a stocktake file against live stock, before anything is written.
/// Shows each product's color/size with current → new quantity, lets the
/// admin resolve shared names and choose what to do with new colors/sizes
/// and unknown products, then applies via [StocktakeCubit.apply].
class StocktakeReviewScreen extends StatefulWidget {
  const StocktakeReviewScreen({super.key});

  @override
  State<StocktakeReviewScreen> createState() => _StocktakeReviewScreenState();
}

class _StocktakeReviewScreenState extends State<StocktakeReviewScreen> {
  _Filter _filter = _Filter.all;

  Future<void> _confirmApply(StocktakeCubit cubit) async {
    final n = cubit.pendingChangeCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الجرد'),
        content: Text(
          'سيتم تطبيق $n تغيير على المخزون.\n'
          'الكميات الحالية ستُستبدل بالكميات الموجودة في الملف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
    if (ok == true) cubit.apply();
  }

  Future<void> _createProduct(List<StocktakeLine> lines) async {
    final stock = <String, Map<String, int>>{};
    String price = '', category = '', threshold = '';
    for (final l in lines) {
      stock.putIfAbsent(l.color, () => {})[l.size] = l.newQty ?? 0;
      final p = cellText(l.row.price),
          c = cellText(l.row.category),
          t = cellText(l.row.threshold);
      if (p.isNotEmpty) price = p;
      if (c.isNotEmpty) category = c;
      if (t.isNotEmpty) threshold = t;
    }
    context.read<InventoryCubit>().prefillNewProduct(
          name: lines.first.fileName,
          stock: stock,
          price: double.tryParse(price),
          category: category,
          threshold: int.tryParse(threshold),
        );
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const AddProductScreen(prefilled: true)),
    );
    if (!mounted) return;
    // A saved product now matches its rows (and they show as unchanged).
    context.read<StocktakeCubit>().reloadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<StocktakeCubit, StocktakeState>(
      listener: (context, state) {
        if (state is StocktakeError) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.message)));
        } else if (state is StocktakeApplied) {
          context.read<InventoryCubit>().fetchProducts(refresh: true);
          context.read<DashboardCubit>().loadDashboard();
        }
      },
      builder: (context, state) {
        final cubit = context.read<StocktakeCubit>();
        final applying = cubit.isApplying;
        return PopScope(
          canPop: !applying,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) cubit.reset();
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('مراجعة الجرد')),
            body: cubit.lastResult != null && !applying
                ? _ResultView(cubit: cubit)
                : cubit.analysis == null
                    ? const Center(child: CircularProgressIndicator())
                    : _buildReview(context, cubit, state),
          ),
        );
      },
    );
  }

  Widget _buildReview(
      BuildContext context, StocktakeCubit cubit, StocktakeState state) {
    final a = cubit.analysis!;
    final applying = cubit.isApplying;

    bool visible(StocktakeLine l) => switch (_filter) {
          _Filter.all => true,
          _Filter.changed =>
            l.isChanged || l.status == StocktakeStatus.newVariant,
          _Filter.review =>
            l.status != StocktakeStatus.matched || l.warning != null,
        };

    // Groups in file order; invalid rows collected last.
    final groups = <String, List<StocktakeLine>>{};
    final invalid = <StocktakeLine>[];
    for (final l in a.lines.where(visible)) {
      if (l.status == StocktakeStatus.invalid) {
        invalid.add(l);
        continue;
      }
      final key = l.product != null
          ? 'p:${l.product!.id}'
          : '${l.status.name}:${l.nameKey}';
      groups.putIfAbsent(key, () => []).add(l);
    }

    final items = <Widget>[
      _WarningBanner(
          fileName: cubit.fileName, modifiedAt: cubit.fileModifiedAt),
      const SizedBox(height: 12),
      _SummaryCards(analysis: a),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: cubit.updateMeta,
        onChanged: applying ? null : cubit.setUpdateMeta,
        title: const Text('تحديث السعر والتصنيف وحد التنبيه أيضاً'),
        subtitle: Text(cubit.updateMeta
            ? 'سيتم تحديث بيانات ${a.metaUpdates.length} منتج من الملف'
            : 'أعمدة السعر والتصنيف وحد التنبيه يتم تجاهلها'),
      ),
      for (final e in a.ambiguousNames.entries)
        _AmbiguousPicker(
          nameKey: e.key,
          displayName: a.lines.firstWhere((l) => l.nameKey == e.key).fileName,
          candidates: e.value,
          selected: cubit.nameChoices[e.key],
          enabled: !applying,
        ),
      if (a.count(StocktakeStatus.newVariant) > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'ألوان/مقاسات جديدة: ${a.count(StocktakeStatus.newVariant)} '
                  '(سيتم إضافة ${cubit.addNewVariantLines.length})',
                ),
              ),
              TextButton(
                onPressed:
                    applying ? null : () => cubit.setAllNewVariants(true),
                child: const Text('إضافة الكل'),
              ),
              TextButton(
                onPressed:
                    applying ? null : () => cubit.setAllNewVariants(false),
                child: const Text('تخطي الكل'),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      SegmentedButton<_Filter>(
        segments: const [
          ButtonSegment(value: _Filter.all, label: Text('الكل')),
          ButtonSegment(value: _Filter.changed, label: Text('المتغير فقط')),
          ButtonSegment(value: _Filter.review, label: Text('يحتاج مراجعة')),
        ],
        selected: {_filter},
        onSelectionChanged: (s) => setState(() => _filter = s.first),
      ),
      const SizedBox(height: 12),
    ];

    final rows = <Widget>[
      for (final g in groups.values) ...[
        _GroupHeader(
          lines: g,
          enabled: !applying,
          onCreate: g.first.status == StocktakeStatus.unknownProduct
              ? () => _createProduct(a.lines
                  .where((l) =>
                      l.status == StocktakeStatus.unknownProduct &&
                      l.nameKey == g.first.nameKey)
                  .toList())
              : null,
        ),
        for (final l in g)
          _LineTile(
            line: l,
            added: cubit.addNewVariantLines.contains(l.row.line),
            enabled: !applying,
          ),
        const SizedBox(height: 12),
      ],
      if (invalid.isNotEmpty) ...[
        _GroupHeader(
            lines: invalid,
            enabled: false,
            title: 'أسطر غير صالحة (سيتم تخطيها)'),
        for (final l in invalid)
          _LineTile(line: l, added: false, enabled: false),
      ],
      if (groups.isEmpty && invalid.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('لا توجد أسطر في هذا العرض')),
        ),
    ];

    final pending = cubit.pendingChangeCount;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length + rows.length,
            itemBuilder: (context, i) =>
                i < items.length ? items[i] : rows[i - items.length],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: applying && state is StocktakeApplying
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value:
                            state.total == 0 ? null : state.done / state.total,
                      ),
                      const SizedBox(height: 8),
                      Text('جارٍ التطبيق: ${state.done} / ${state.total} منتج'),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: applying
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: applying || pending == 0
                              ? null
                              : () => _confirmApply(cubit),
                          child: Text(pending == 0
                              ? 'لا توجد تغييرات'
                              : 'تطبيق الجرد ($pending)'),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String fileName;
  final DateTime? modifiedAt;
  const _WarningBanner({required this.fileName, required this.modifiedAt});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: Colors.orange.shade900);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange.shade800, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'الجرد يستبدل الكميات الحالية بالكميات الموجودة في الملف. '
                  'أي طلبات تمت بعد تصدير الملف ستتأثر.',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('الملف: $fileName', style: style),
          if (modifiedAt != null)
            Text('آخر تعديل للملف: ${_dateTime(modifiedAt!)}', style: style),
          Text('الوقت الحالي: ${_dateTime(DateTime.now())}', style: style),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final StocktakeAnalysis analysis;
  const _SummaryCards({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final ambiguous = a.count(StocktakeStatus.ambiguous);
    final cards = [
      ('إجمالي الأسطر', a.lines.length, Colors.blueGrey),
      ('مطابق', a.count(StocktakeStatus.matched), Colors.green),
      ('كمية متغيرة', a.changedCount, Colors.blue),
      ('بدون تغيير', a.unchangedCount, Colors.grey),
      ('لون/مقاس جديد', a.count(StocktakeStatus.newVariant), Colors.purple),
      (
        'منتج غير معروف',
        a.count(StocktakeStatus.unknownProduct),
        Colors.orange
      ),
      if (ambiguous > 0) ('اسم مشترك', ambiguous, Colors.deepOrange),
      ('غير صالح', a.count(StocktakeStatus.invalid), Colors.red),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, value, color) in cards)
          Container(
            width: 104,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color.shade800)),
                Text(label,
                    style: TextStyle(fontSize: 11, color: color.shade900)),
              ],
            ),
          ),
      ],
    );
  }
}

class _AmbiguousPicker extends StatelessWidget {
  final String nameKey;
  final String displayName;
  final List<StocktakeProduct> candidates;
  final String? selected;
  final bool enabled;
  const _AmbiguousPicker({
    required this.nameKey,
    required this.displayName,
    required this.candidates,
    required this.selected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.deepOrange.shade50,
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الاسم «$displayName» مشترك بين ${candidates.length} منتجات — اختر المنتج المقصود أو تخطَّ أسطره',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              isExpanded: true,
              value: selected,
              hint: const Text('يحتاج اختيار (يتم التخطي حاليًا)'),
              onChanged: enabled
                  ? (v) => context
                      .read<StocktakeCubit>()
                      .setNameChoice(nameKey, v ?? '')
                  : null,
              items: [
                for (final p in candidates)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      '${p.name} — ${p.category} — ${p.totalQty} قطعة — ${p.colors.join('/')} (${p.id})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const DropdownMenuItem(
                    value: '', child: Text('تخطي هذه الأسطر')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final List<StocktakeLine> lines;
  final bool enabled;
  final String? title;
  final VoidCallback? onCreate;
  const _GroupHeader(
      {required this.lines, required this.enabled, this.title, this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = lines.first;
    final changed = lines.where((l) => l.isChanged).length;
    final String subtitle = switch (first.status) {
      StocktakeStatus.unknownProduct => 'منتج غير موجود — تخطي (افتراضي)',
      StocktakeStatus.ambiguous => 'اسم مشترك — اختر المنتج أعلاه',
      _ when title != null => '',
      _ => changed == 0 ? 'بدون تغيير' : '$changed كمية متغيرة',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title ?? first.product?.name ?? first.fileName,
                    style: theme.textTheme.titleMedium),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (onCreate != null)
            OutlinedButton.icon(
              onPressed: enabled ? onCreate : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('إنشاء منتج جديد'),
            ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  final StocktakeLine line;
  final bool added;
  final bool enabled;
  const _LineTile(
      {required this.line, required this.added, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = line;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget trailing;
    switch (l.status) {
      case StocktakeStatus.matched:
        final delta = l.newQty! - l.current!;
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${l.current} → ${l.newQty}',
                textDirection: TextDirection.ltr),
            const SizedBox(width: 8),
            _DeltaChip(delta: delta),
          ],
        );
      case StocktakeStatus.newVariant:
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${l.newQty}'),
            const SizedBox(width: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: true, label: Text('إضافة')),
                ButtonSegment(value: false, label: Text('تخطي')),
              ],
              selected: {added},
              onSelectionChanged: enabled
                  ? (s) => context
                      .read<StocktakeCubit>()
                      .setAddNewVariant(l.row.line, s.first)
                  : null,
            ),
          ],
        );
      case StocktakeStatus.invalid:
        trailing = const SizedBox.shrink();
      case StocktakeStatus.unknownProduct || StocktakeStatus.ambiguous:
        trailing = Text('${l.newQty ?? ''}', style: muted);
    }

    final badge = switch (l.status) {
      StocktakeStatus.newVariant => l.isNewColor ? 'لون جديد' : 'مقاس جديد',
      _ => null,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      [l.color, l.size].where((s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(badge,
                            style: TextStyle(
                                fontSize: 11, color: Colors.purple.shade800)),
                      ),
                    Text('سطر ${l.row.line}', style: muted),
                  ],
                ),
              ),
              trailing,
            ],
          ),
          if (l.error != null)
            Text(
              [if (l.fileName.isNotEmpty) l.fileName, l.error!].join(' — '),
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          if (l.warning != null)
            Text(l.warning!,
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final int delta;
  const _DeltaChip({required this.delta});

  @override
  Widget build(BuildContext context) {
    final color = delta > 0
        ? Colors.green
        : delta < 0
            ? Colors.red
            : Colors.grey;
    return Container(
      constraints: const BoxConstraints(minWidth: 36),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        delta > 0
            ? '+$delta'
            : delta == 0
                ? '0'
                : '−${-delta}',
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: TextStyle(fontWeight: FontWeight.bold, color: color.shade800),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final StocktakeCubit cubit;
  const _ResultView({required this.cubit});

  @override
  Widget build(BuildContext context) {
    final r = cubit.lastResult!;
    final failed = r.failures.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          failed ? Icons.error_outline : Icons.check_circle_outline,
          size: 56,
          color: failed ? Colors.orange : Colors.green,
        ),
        const SizedBox(height: 12),
        Text(
          'تم تحديث ${r.updatedSizes} مقاس في ${r.updatedProducts} منتج',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (failed) ...[
          const SizedBox(height: 16),
          Text('فشل تطبيق ${r.failures.length} منتج:',
              style: TextStyle(
                  color: Colors.red.shade700, fontWeight: FontWeight.bold)),
          for (final f in r.failures)
            Text('• ${f.productName}: ${f.error}',
                style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: cubit.retryFailed,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة للمنتجات الفاشلة'),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('تم'),
        ),
      ],
    );
  }
}
