import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/jordan_phone.dart';

/// Delivery/return stats one order contributes to its customer.
///
/// Definitions (used both by the live order transactions and by the repair
/// recompute, so the two can never disagree):
/// - an item counts as delivered when its status is `delivered`, or when it
///   is still `pending` inside an order the owner marked `completed`;
/// - an item counts as returned when its status is `returned`;
/// - [deliveredCount] is 1 if the order has at least one delivered item;
/// - [deliveredValue] is the delivered items' `unitPrice × quantity`, scaled
///   by the order's net `total` / gross so a cart discount is shared across
///   items. Manual orders carry no prices, so they contribute 0;
/// - [returnedCount] is the number of returned items (lines).
class OrderCustomerStats {
  final int deliveredCount;
  final double deliveredValue;
  final int returnedCount;

  const OrderCustomerStats({
    this.deliveredCount = 0,
    this.deliveredValue = 0,
    this.returnedCount = 0,
  });

  /// Computed from the raw Firestore order map (raw so `unitPrice` is seen
  /// even where the app model doesn't use it).
  factory OrderCustomerStats.fromOrderData(Map<String, dynamic> order) {
    final orderStatus = order['status'] as String? ?? 'pending';
    final items = (order['items'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    double lineValue(Map<String, dynamic> m) =>
        ((m['unitPrice'] as num?)?.toDouble() ?? 0) *
        ((m['quantity'] as num?)?.toDouble() ?? 0);

    final gross = items.fold<double>(0, (s, m) => s + lineValue(m));
    final total = (order['total'] as num?)?.toDouble();
    final ratio = (total != null && gross > 0) ? total / gross : 1.0;

    var delivered = 0;
    var value = 0.0;
    var returned = 0;
    for (final m in items) {
      final status = m['status'] as String? ?? 'pending';
      if (status == 'returned') {
        returned++;
      } else if (status == 'delivered' ||
          (status == 'pending' && orderStatus == 'completed')) {
        delivered++;
        value += lineValue(m) * ratio;
      }
    }
    return OrderCustomerStats(
      deliveredCount: delivered > 0 ? 1 : 0,
      deliveredValue: value,
      returnedCount: returned,
    );
  }
}

/// `customers/{id}` for the phone stored on an order, or null if the phone
/// can't be normalised.
DocumentReference<Map<String, dynamic>>? customerRefForOrder(
  FirebaseFirestore db,
  Map<String, dynamic> orderData,
) {
  final phone = normalizePhoneE164(orderData['customerPhone'] as String? ?? '');
  return phone == null ? null : db.collection('customers').doc(phone);
}

/// Applies the before → after stats change of one order to its customer
/// inside [tx]. The caller must have read [customerSnap] in the same
/// transaction (before any write). Because before/after both come from the
/// live order read in that transaction, a repeated tap sees no change and
/// writes nothing — no blind increments.
///
/// Customers that don't exist (orders from before the customers collection)
/// are skipped rather than half-created.
void applyCustomerStatsChange(
  Transaction tx,
  DocumentSnapshot<Map<String, dynamic>>? customerSnap, {
  required Map<String, dynamic> before,
  required Map<String, dynamic> after,
}) {
  if (customerSnap == null || !customerSnap.exists) return;
  final b = OrderCustomerStats.fromOrderData(before);
  final a = OrderCustomerStats.fromOrderData(after);
  final dCount = a.deliveredCount - b.deliveredCount;
  final dValue = a.deliveredValue - b.deliveredValue;
  final dReturned = a.returnedCount - b.returnedCount;
  if (dCount == 0 && dValue.abs() < 0.0001 && dReturned == 0) return;
  tx.update(customerSnap.reference, {
    if (dCount != 0) 'deliveredCount': FieldValue.increment(dCount),
    if (dValue.abs() >= 0.0001) 'deliveredValue': FieldValue.increment(dValue),
    if (dReturned != 0) 'returnedCount': FieldValue.increment(dReturned),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

DateTime? _orderDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// Repair tool: rebuilds every counter of one customer from their orders
/// (ordersCount, totalOrdersValue, first/last order, delivered/returned
/// stats). Returns the number of orders found. Throws if the customer
/// document doesn't exist.
Future<int> recomputeCustomerStats(FirebaseFirestore db, String phone) async {
  final ref = db.collection('customers').doc(phone);
  final snap = await ref.get();
  if (!snap.exists) throw Exception('العميل غير موجود.');

  final orders = await db
      .collection('orders')
      .where('customerPhone', isEqualTo: phone)
      .get();

  var ordersCount = 0;
  var totalValue = 0.0;
  var deliveredCount = 0;
  var deliveredValue = 0.0;
  var returnedCount = 0;
  DateTime? first;
  DateTime? last;
  for (final doc in orders.docs) {
    final data = doc.data();
    ordersCount++;
    totalValue += (data['total'] as num?)?.toDouble() ?? 0;
    final s = OrderCustomerStats.fromOrderData(data);
    deliveredCount += s.deliveredCount;
    deliveredValue += s.deliveredValue;
    returnedCount += s.returnedCount;
    final at = _orderDate(data['createdAt']);
    if (at != null) {
      if (first == null || at.isBefore(first)) first = at;
      if (last == null || at.isAfter(last)) last = at;
    }
  }

  await ref.update({
    'ordersCount': ordersCount,
    'totalOrdersValue': totalValue,
    'deliveredCount': deliveredCount,
    'deliveredValue': deliveredValue,
    'returnedCount': returnedCount,
    if (first != null) 'firstOrderAt': Timestamp.fromDate(first),
    if (last != null) 'lastOrderAt': Timestamp.fromDate(last),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  return ordersCount;
}
