import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/order/order_cubit.dart';
import '../../cubit/order/order_state.dart';
import '../../data/order/order_model.dart';
import 'create_order.dart';
import 'widgets/order_card.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  @override
  void initState() {
    super.initState();
    context.read<OrderCubit>().fetchOrders();
  }

  static const double _maxContentWidth = 1600;

  /// <600: 1 (list), 600–899: 2, 900–1279: 3, ≥1280: 4.
  static int _columnsFor(double width) {
    if (width < 600) return 1;
    if (width < 900) return 2;
    if (width < 1280) return 3;
    return 4;
  }

  /// Full order card: a centered dialog on ≥900px, a page on tablets.
  void _openDetails(BuildContext context, OrderModel order, double width) {
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
                    child: _LiveOrderCard(order: order),
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
                child: _LiveOrderCard(order: order),
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
      body: BlocConsumer<OrderCubit, OrderState>(
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
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
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
              Expanded(
                child: Builder(builder: (context) {
                  if (state is OrderLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final orders = cubit.orders;
                  if (orders.isEmpty) {
                    return const Center(child: Text('لا توجد طلبات بعد'));
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
                          padding: EdgeInsets.fromLTRB(side, 16, side, 96),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            mainAxisExtent: kOrderSummaryCardHeight * textScale,
                          ),
                          itemCount: orders.length,
                          itemBuilder: (context, index) => OrderSummaryCard(
                            order: orders[index],
                            onTap: () =>
                                _openDetails(context, orders[index], width),
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
