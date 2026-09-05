import 'package:flutter/material.dart';

import 'orders/order_list.dart';
import 'products/product_list.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  static const _screens = [ProductListScreen(), OrderListScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'المنتجات'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'الطلبات'),
        ],
      ),
    );
  }
}
