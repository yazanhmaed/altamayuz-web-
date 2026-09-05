import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/order/order_cubit.dart';
import '../../cubit/order/order_state.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الطلبات')),
      body: BlocConsumer<OrderCubit, OrderState>(
        listener: (context, state) {
          if (state is OrderError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          if (state is OrderLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = context.read<OrderCubit>().orders;
          if (orders.isEmpty) {
            return const Center(child: Text('لا توجد طلبات بعد'));
          }
          return RefreshIndicator(
            onRefresh: () => context.read<OrderCubit>().fetchOrders(refresh: true),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, index) => OrderCard(order: orders[index]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.read<OrderCubit>().clearForm();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateOrderScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('طلب جديد'),
      ),
    );
  }
}
