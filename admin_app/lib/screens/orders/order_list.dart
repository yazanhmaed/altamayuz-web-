import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../cubit/order/order_cubit.dart';
import '../../cubit/order/order_state.dart';
import '../../data/order/order_model.dart';
import '../../utils/order_search.dart';
import 'create_order.dart';
import 'widgets/order_card.dart';
import 'widgets/qr_scanner_screen.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  /// Barcode lookup in flight; [_lookupSeq] drops answers to older scans.
  bool _lookingUp = false;
  int _lookupSeq = 0;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<OrderCubit>();
    _searchCtrl.text = cubit.searchQuery;
    cubit.fetchOrders();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250),
        () => context.read<OrderCubit>().setSearchQuery(text));
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    context.read<OrderCubit>().setSearchQuery('');
  }

  Future<void> _scanBarcode() async {
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => const QrScanDialog(),
    );
    if (!mounted || raw == null || raw.trim().isEmpty) return;
    await _lookupBarcode(raw);
  }

  /// Finds the order(s) holding [raw] in `qrCode`, in any status, and opens
  /// it, lets the user pick among duplicates, or offers a rescan.
  Future<void> _lookupBarcode(String raw) async {
    final code = normalizeBarcode(raw);
    if (code.isEmpty) return;
    final seq = ++_lookupSeq;
    setState(() => _lookingUp = true);
    List<OrderModel> found;
    try {
      found = await context.read<OrderCubit>().findOrderByBarcode(code);
    } catch (e) {
      if (!mounted || seq != _lookupSeq) return;
      setState(() => _lookingUp = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_lookupErrorMessage(e))));
      return;
    }
    if (!mounted || seq != _lookupSeq) return;
    setState(() => _lookingUp = false);

    final width = MediaQuery.sizeOf(context).width;
    if (found.length == 1) {
      _openDetails(context, found.single, width, foundByBarcode: true);
    } else if (found.isEmpty) {
      await _showBarcodeNotFound(code);
    } else {
      final picked = await _pickDuplicateOrder(found);
      if (picked != null && mounted) {
        _openDetails(context, picked, width, foundByBarcode: true);
      }
    }
  }

  static String _lookupErrorMessage(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return 'لا تملك صلاحية البحث في الطلبات';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'تعذر الاتصال بالخادم، تحقق من الإنترنت وحاول مرة أخرى';
      }
    }
    return 'تعذر البحث بالرمز، حاول مرة أخرى';
  }

  Future<void> _showBarcodeNotFound(String code) async {
    final rescan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('لا توجد نتيجة'),
        content: Text('لم يتم العثور على طلب بهذا الرمز: $code'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إغلاق'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('مسح مرة أخرى'),
          ),
        ],
      ),
    );
    if (rescan == true && mounted) await _scanBarcode();
  }

  Future<OrderModel?> _pickDuplicateOrder(List<OrderModel> found) {
    return showModalBottomSheet<OrderModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.warning_amber_rounded,
                      color: theme.colorScheme.error),
                  title: const Text('الرمز مكرر في أكثر من طلب'),
                  subtitle: const Text('اختر الطلب المطلوب'),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final o in found)
                        ListTile(
                          title: Text(o.customerName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              o.customerPhone,
                              DateFormat('d MMM yyyy', 'ar')
                                  .format(o.createdAt),
                              _statusLabels[o.status]!,
                              o.total != null
                                  ? '${o.total!.toStringAsFixed(2)} د.أ'
                                  : '—',
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => Navigator.of(ctx).pop(o),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _statusLabels = {
    OrderStatus.pending: 'معلّق',
    OrderStatus.shipped: 'مشحون',
    OrderStatus.completed: 'مكتمل',
    OrderStatus.returned: 'مرتجع',
  };

  static const double _maxContentWidth = 1600;

  /// <600: 1 (list), 600–899: 2, 900–1279: 3, ≥1280: 4.
  /// Search text that could be a code: one non-empty word.
  static bool _isCodeQuery(String query) {
    final q = normalizeBarcode(query);
    return q.isNotEmpty && !q.contains(RegExp(r'\s'));
  }

  static int _columnsFor(double width) {
    if (width < 600) return 1;
    if (width < 900) return 2;
    if (width < 1280) return 3;
    return 4;
  }

  /// Full order card: a centered dialog on ≥900px, a page on tablets.
  void _openDetails(BuildContext context, OrderModel order, double width,
      {bool foundByBarcode = false}) {
    Widget details = _LiveOrderCard(order: order);
    if (foundByBarcode) {
      details = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: Chip(
              avatar: Icon(Icons.qr_code_scanner, size: 18),
              label: Text('تم العثور عليه بالباركود'),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 8),
          details,
        ],
      );
    }
    if (width >= 900) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('تفاصيل الطلب',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      const CloseButton(),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: details,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('تفاصيل الطلب')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: details,
              ),
            ),
          ),
        ),
      ));
    }
  }

  static const _filterLabels = {
    OrderFilter.active: 'نشط',
    OrderFilter.all: 'الكل',
    OrderFilter.pending: 'معلّق',
    OrderFilter.shipped: 'مشحون',
    OrderFilter.completed: 'مكتمل',
    OrderFilter.returned: 'مرتجع',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الطلبات')),
      body: Column(
        children: [
          // Outside the BlocConsumer: typing never rebuilds the field.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchCtrl,
                      builder: (context, value, _) => TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        onChanged: _onSearchChanged,
                        onSubmitted: (text) {
                          _searchDebounce?.cancel();
                          context.read<OrderCubit>().setSearchQuery(text);
                          // Hardware scanners type the code then Enter.
                          if (looksLikeBarcode(text)) _lookupBarcode(text);
                        },
                        decoration: InputDecoration(
                          hintText: 'ابحث بالاسم أو الهاتف أو رقم الطلب',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (value.text.isNotEmpty)
                                IconButton(
                                  tooltip: 'مسح البحث',
                                  icon: const Icon(Icons.close),
                                  onPressed: _clearSearch,
                                ),
                              IconButton(
                                tooltip: 'بحث بالباركود',
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: _lookingUp ? null : _scanBarcode,
                              ),
                            ],
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),
                    if (_lookingUp)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 4, 24, 0),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: BlocConsumer<OrderCubit, OrderState>(
              listener: (context, state) {
                if (state is OrderError) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(state.message)));
                }
              },
              builder: (context, state) {
                final cubit = context.read<OrderCubit>();
                return Column(
                  children: [
                    // Aligned with the grid's max width on wide screens; on phones
                    // this is the same full-width row as before.
                    Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: _maxContentWidth),
                        child: SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final filter in OrderFilter.values)
                                  ChoiceChip(
                                    label: Text(_filterLabels[filter]!),
                                    selected: cubit.currentFilter == filter,
                                    onSelected: (_) =>
                                        cubit.fetchOrders(filter: filter),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (cubit.isSearching && state is! OrderLoading)
                      Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: _maxContentWidth),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text(
                                  '${cubit.visibleOrders.length} من ${cubit.orders.length} طلباً محمّلاً',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (_isCodeQuery(cubit.searchQuery))
                                  TextButton.icon(
                                    onPressed: _lookingUp
                                        ? null
                                        : () =>
                                            _lookupBarcode(cubit.searchQuery),
                                    icon: const Icon(Icons.qr_code_2, size: 18),
                                    label: const Text('بحث بالرمز'),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Builder(builder: (context) {
                        if (state is OrderLoading) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (cubit.orders.isEmpty) {
                          return const Center(child: Text('لا توجد طلبات بعد'));
                        }
                        final orders = cubit.visibleOrders;
                        if (orders.isEmpty) {
                          return _NoSearchResults(
                            onClear: _clearSearch,
                            onBarcodeSearch:
                                _isCodeQuery(cubit.searchQuery) && !_lookingUp
                                    ? () => _lookupBarcode(cubit.searchQuery)
                                    : null,
                            onLoadMore: cubit.hasMoreOrders
                                ? cubit.loadMoreOrders
                                : null,
                          );
                        }
                        return RefreshIndicator(
                          onRefresh: () => cubit.fetchOrders(refresh: true),
                          child: LayoutBuilder(builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final columns = _columnsFor(width);
                            // Phones: the original full-card list, unchanged.
                            if (columns == 1) {
                              return ListView.builder(
                                padding: const EdgeInsets.all(16),
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                itemCount: orders.length,
                                itemBuilder: (context, index) =>
                                    OrderCard(order: orders[index]),
                              );
                            }
                            // Wider: grid of compact summaries, centered at a max
                            // width. Fixed card height (content is single-line and
                            // ellipsized), scaled with the text size.
                            final side = width > _maxContentWidth
                                ? (width - _maxContentWidth) / 2 + 16
                                : 16.0;
                            final textScale = MediaQuery.textScalerOf(context)
                                .scale(1)
                                .clamp(1.0, 1.3);
                            return MediaQuery.withClampedTextScaling(
                              maxScaleFactor: 1.3,
                              child: GridView.builder(
                                padding:
                                    EdgeInsets.fromLTRB(side, 16, side, 96),
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent:
                                      kOrderSummaryCardHeight * textScale,
                                ),
                                itemCount: orders.length,
                                itemBuilder: (context, index) =>
                                    OrderSummaryCard(
                                  order: orders[index],
                                  onTap: () => _openDetails(
                                      context, orders[index], width),
                                ),
                              ),
                            );
                          }),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.read<OrderCubit>().clearForm();
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateOrderScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('طلب جديد'),
      ),
    );
  }
}

/// The full [OrderCard] for one order, rebuilt when the cubit emits (status,
/// item and QR actions update the order in place).
class _LiveOrderCard extends StatelessWidget {
  final OrderModel order;
  const _LiveOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrderCubit, OrderState>(
      builder: (context, _) {
        final orders = context.read<OrderCubit>().orders;
        final current = orders.firstWhere(
          (o) => o.id == order.id,
          orElse: () => order,
        );
        return OrderCard(order: current);
      },
    );
  }
}

/// Search matched none of the loaded orders. [onLoadMore] is set when the
/// server has more orders for the current filter.
class _NoSearchResults extends StatelessWidget {
  final VoidCallback onClear;
  final VoidCallback? onLoadMore;

  /// Set when the query could be a code: looks it up in every status.
  final VoidCallback? onBarcodeSearch;
  const _NoSearchResults(
      {required this.onClear, this.onLoadMore, this.onBarcodeSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('لا توجد نتائج ضمن الطلبات المحمّلة',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onClear,
                  child: const Text('مسح البحث'),
                ),
                if (onBarcodeSearch != null)
                  FilledButton.tonalIcon(
                    onPressed: onBarcodeSearch,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('بحث بالرمز'),
                  ),
                if (onLoadMore != null)
                  FilledButton.tonal(
                    onPressed: onLoadMore,
                    child: const Text('تحميل المزيد من الطلبات'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
