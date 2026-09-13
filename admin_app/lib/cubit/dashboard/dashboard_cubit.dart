import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/order/order_model.dart';
import 'dashboard_state.dart';

class LowStockEntry {
  final String productId;
  final String productName;
  final String color;
  final String size;
  final int quantity;
  final int threshold;
  LowStockEntry({
    required this.productId,
    required this.productName,
    required this.color,
    required this.size,
    required this.quantity,
    required this.threshold,
  });
}

class DashboardData {
  final int orderCount;
  final String? topProductName;
  final int topProductQty;
  final String? topSize;
  final int topSizeQty;
  final int manualOrderCount;
  final int storefrontOrderCount;
  final List<LowStockEntry> lowStockEntries;
  const DashboardData({
    required this.orderCount,
    this.topProductName,
    required this.topProductQty,
    this.topSize,
    required this.topSizeQty,
    required this.manualOrderCount,
    required this.storefrontOrderCount,
    required this.lowStockEntries,
  });
}

/// Focused, single-purpose cubit for the dashboard tab's metrics — mirrors
/// [InventoryCubit]/`OrderCubit` as a separate cubit rather than overloading
/// either with unrelated aggregation concerns. Every "this month" metric is
/// queried directly from Firestore scoped to the current calendar month
/// (never a fetch of the full historical `orders` collection); the low-stock
/// check is a live, unscoped read over `products` (naturally bounded catalog
/// size, same as [InventoryCubit.fetchProducts]).
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit() : super(DashboardInitial());
  final _db = FirebaseFirestore.instance;

  /// The currently-active range, defaulting to the current calendar month.
  /// Exposed so the UI can display what's actually loaded; updated in
  /// [loadDashboard] whenever a new `from`/`to` is passed.
  DateTime currentFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime currentTo = DateTime.now();

  /// Loads every date-scoped metric (order count, best-selling product,
  /// most-requested size, source distribution) for [from]..[to] — defaults
  /// to whatever range is already active when not provided. The low-stock
  /// section below queries `products` independently and is never date-scoped.
  Future<void> loadDashboard({DateTime? from, DateTime? to}) async {
    currentFrom = from ?? currentFrom;
    currentTo = to ?? currentTo;
    emit(DashboardLoading());
    try {
      final ordersSnap = await _db
          .collection('orders')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(currentFrom))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(currentTo))
          .get();
      final monthOrders =
          ordersSnap.docs.map((d) => OrderModel.fromMap(d.data())).toList();

      final Map<String, int> productQty = {};
      final Map<String, int> sizeQty = {};
      var manualCount = 0, storefrontCount = 0;
      for (final o in monthOrders) {
        if (o.source == 'manual') {
          manualCount++;
        } else {
          storefrontCount++;
        }
        for (final item in o.items) {
          final key = item.productName ?? item.productId;
          productQty[key] = (productQty[key] ?? 0) + item.quantity;
          sizeQty[item.size] = (sizeQty[item.size] ?? 0) + item.quantity;
        }
      }
      String? topProduct, topSize;
      var topProductQty = 0, topSizeQty = 0;
      productQty.forEach((k, v) {
        if (v > topProductQty) {
          topProduct = k;
          topProductQty = v;
        }
      });
      sizeQty.forEach((k, v) {
        if (v > topSizeQty) {
          topSize = k;
          topSizeQty = v;
        }
      });

      final productsSnap =
          await _db.collection('products').where('isActive', isEqualTo: true).get();
      final List<LowStockEntry> lowStock = [];
      for (final doc in productsSnap.docs) {
        final data = doc.data();
        final threshold = (data['lowStockThreshold'] as num?)?.toInt() ?? 1;
        final stock = Map<String, dynamic>.from(data['stock'] as Map? ?? {});
        stock.forEach((color, sizes) {
          Map<String, dynamic>.from(sizes as Map).forEach((size, qty) {
            final q = (qty as num).toInt();
            if (q <= threshold) {
              lowStock.add(LowStockEntry(
                productId: doc.id,
                productName: data['name'] as String? ?? doc.id,
                color: color,
                size: size,
                quantity: q,
                threshold: threshold,
              ));
            }
          });
        });
      }

      emit(DashboardLoaded(DashboardData(
        orderCount: monthOrders.length,
        topProductName: topProduct,
        topProductQty: topProductQty,
        topSize: topSize,
        topSizeQty: topSizeQty,
        manualOrderCount: manualCount,
        storefrontOrderCount: storefrontCount,
        lowStockEntries: lowStock,
      )));
    } catch (e) {
      emit(DashboardError(e.toString()));
    }
  }

  void resetToCurrentMonth() {
    final now = DateTime.now();
    loadDashboard(from: DateTime(now.year, now.month, 1), to: now);
  }
}
