import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/order/order_model.dart';
import '../../data/order/pick_result_model.dart';
import '../../screens/orders/widgets/qr_scanner_screen.dart';
import '../../utils/jordan_phone.dart';
import 'order_state.dart';

class OrderCubit extends Cubit<OrderState> {
  OrderCubit() : super(OrderInitial());

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<OrderModel> orders = [];
  bool _hasFetched = false;

  // ---- create/edit order form state ----
  final customerNameCtrl = TextEditingController();
  final customerPhoneCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final areaCtrl = TextEditingController();
  final streetCtrl = TextEditingController();
  final destinationCtrl = TextEditingController();
  final deliveryDateCtrl = TextEditingController();
  final qrCodeCtrl = TextEditingController();
  final List<OrderItem> selectedItems = [];
  OrderModel? editingOrder;

  Future<void> fetchOrders({bool refresh = false}) async {
    if (_hasFetched && !refresh) {
      emit(OrderLoaded(orders));
      return;
    }
    emit(OrderLoading());
    try {
      final snap = await _db.collection('orders').orderBy('createdAt', descending: true).get();
      orders = snap.docs.map((d) => OrderModel.fromMap(d.data())).toList();
      _hasFetched = true;
      emit(OrderLoaded(orders));
    } catch (e) {
      emit(OrderError(e.toString()));
    }
  }

  // ---------------------------------------------------------------------
  // Create/edit order form
  // ---------------------------------------------------------------------

  void addItem(PickResult pick, int quantity) {
    selectedItems.add(
      OrderItem(
        itemId: _db.collection('_').doc().id,
        productId: pick.productId,
        productName: pick.productName,
        color: pick.color,
        size: pick.size,
        sku: pick.sku,
        quantity: quantity,
        qrCode: '',
        isPrimary: selectedItems.isEmpty,
      ),
    );
    emit(OrderFormChanged());
  }

  void removeItem(int index) {
    if (index < 0 || index >= selectedItems.length) return;
    selectedItems.removeAt(index);
    emit(OrderFormChanged());
  }

  void clearForm() {
    editingOrder = null;
    customerNameCtrl.clear();
    customerPhoneCtrl.clear();
    addressCtrl.clear();
    areaCtrl.clear();
    streetCtrl.clear();
    destinationCtrl.clear();
    deliveryDateCtrl.clear();
    qrCodeCtrl.clear();
    selectedItems.clear();
    emit(OrderFormChanged());
  }

  void loadOrderForEditing(OrderModel orderModel) {
    editingOrder = orderModel;
    customerNameCtrl.text = orderModel.customerName;
    customerPhoneCtrl.text = jordanPhoneToLocal(orderModel.customerPhone);
    addressCtrl.text = orderModel.address;
    areaCtrl.text = orderModel.area;
    streetCtrl.text = orderModel.street;
    destinationCtrl.text = orderModel.destination;
    deliveryDateCtrl.text = orderModel.deliveryDate;
    qrCodeCtrl.text = orderModel.qrCode.isNotEmpty ? orderModel.qrCode.first : '';
    selectedItems
      ..clear()
      ..addAll(orderModel.items);
    emit(OrderFormChanged());
  }

  OrderModel _buildOrder({required String id}) {
    return OrderModel(
      id: id,
      customerName: customerNameCtrl.text.trim(),
      // Stored in the same E164 form the storefront uses (jordanPhoneToE164),
      // so admin- and storefront-created orders match. Empty stays empty.
      customerPhone: customerPhoneCtrl.text.trim().isEmpty
          ? ''
          : jordanPhoneToE164(customerPhoneCtrl.text.trim()),
      destination: destinationCtrl.text.trim(),
      address: addressCtrl.text.trim(),
      area: areaCtrl.text.trim(),
      street: streetCtrl.text.trim(),
      items: List.of(selectedItems),
      qrCode: qrCodeCtrl.text.trim().isNotEmpty
          ? [qrCodeCtrl.text.trim()]
          : (editingOrder?.qrCode ?? []),
      createdAt: editingOrder?.createdAt ?? DateTime.now(),
      status: editingOrder?.status ?? OrderStatus.pending,
      deliveryDate: deliveryDateCtrl.text.trim(),
      source: editingOrder?.source ?? 'manual',
      // Money fields are owned by the storefront function; carry them through
      // an owner edit unchanged (null for manual orders).
      subtotal: editingOrder?.subtotal,
      cartDiscountAmount: editingOrder?.cartDiscountAmount,
      cartDiscountTierMinQuantity: editingOrder?.cartDiscountTierMinQuantity,
      total: editingOrder?.total,
    );
  }

  /// Saves an order and keeps inventory in sync in a single transaction:
  /// a new order deducts every ordered unit; an edited order moves only the
  /// net delta vs. what was previously stored. Quantities are aggregated per
  /// product/color/size first so each product document only ever receives one
  /// `tx.update()` call — the same anti-clobber pattern used when restocking
  /// returns.
  Future<void> submitOrder() async {
    if (customerNameCtrl.text.trim().isEmpty || customerPhoneCtrl.text.trim().isEmpty) {
      emit(OrderError('اسم الزبون ورقم الهاتف مطلوبان.'));
      return;
    }
    if (selectedItems.isEmpty) {
      emit(OrderError('أضف قطعة واحدة على الأقل للطلب.'));
      return;
    }

    emit(OrderFormLoadChanged());
    try {
      final isNewOrder = editingOrder == null;
      final orderRef = isNewOrder ? _db.collection('orders').doc() : _db.collection('orders').doc(editingOrder!.id);
      final order = _buildOrder(id: orderRef.id);

      if (isNewOrder) {
        await _db.runTransaction((tx) async {
          final Map<String, Map<String, Map<String, int>>> need = {};
          for (final item in order.items) {
            need
                .putIfAbsent(item.productId, () => {})
                .putIfAbsent(item.color, () => {})
                .update(item.size, (v) => v + item.quantity, ifAbsent: () => item.quantity);
          }

          final Map<String, Map<String, dynamic>> productData = {};
          for (final productId in need.keys) {
            final ref = _db.collection('products').doc(productId);
            final snap = await tx.get(ref);
            if (!snap.exists) {
              throw Exception('المنتج ($productId) غير موجود.');
            }
            productData[productId] = Map<String, dynamic>.from(snap.data()!);
          }

          for (final productId in need.keys) {
            final ref = _db.collection('products').doc(productId);
            final data = productData[productId]!;
            final stock = Map<String, dynamic>.from(data['stock'] as Map? ?? {});

            for (final colorEntry in need[productId]!.entries) {
              final color = colorEntry.key;
              final colorMap = Map<String, dynamic>.from(stock[color] ?? <String, dynamic>{});
              for (final sizeEntry in colorEntry.value.entries) {
                final current = (colorMap[sizeEntry.key] as num?)?.toInt() ?? 0;
                final remaining = current - sizeEntry.value;
                if (remaining < 0) {
                  throw Exception(
                    'الكمية غير كافية للمنتج (${data['name']}) - $color - ${sizeEntry.key}.',
                  );
                }
                colorMap[sizeEntry.key] = remaining;
              }
              stock[color] = colorMap;
            }

            tx.update(ref, {
              'stock': stock,
              'updatedAt': DateTime.now().toIso8601String(),
            });
          }

          tx.set(orderRef, order.toMap());
        });
      } else {
        // Editing an existing order: stock was already deducted when the order
        // was first created, so we must move only the NET DELTA per
        // product/color/size — deduct where the new quantity is higher,
        // restore where it is lower. A plain `.set()` here would silently
        // desync inventory. Delta is aggregated per product so each product
        // doc gets exactly one tx.update(), the same anti-clobber pattern used
        // for order creation and return-restocking. Do NOT "simplify" this
        // back into a bare set().
        await _db.runTransaction((tx) async {
          // ---- reads first (Firestore requires all reads before any write) ----
          final orderSnap = await tx.get(orderRef);
          if (!orderSnap.exists) {
            throw Exception('الطلب غير موجود.');
          }
          final storedOrder = OrderModel.fromMap(orderSnap.data()!);

          // A returned order already gave its stock back; leave inventory
          // untouched and just persist the edited fields.
          if (storedOrder.status == OrderStatus.returned) {
            tx.set(orderRef, order.toMap());
            return;
          }

          // net delta: + for extra units to deduct, - for units to restore.
          final Map<String, Map<String, Map<String, int>>> delta = {};
          void bump(String p, String c, String s, int q) {
            delta
                .putIfAbsent(p, () => {})
                .putIfAbsent(c, () => {})
                .update(s, (v) => v + q, ifAbsent: () => q);
          }
          for (final item in storedOrder.items) {
            bump(item.productId, item.color, item.size, -item.quantity);
          }
          for (final item in order.items) {
            bump(item.productId, item.color, item.size, item.quantity);
          }
          // drop variants whose quantity did not change
          delta.forEach((_, colors) {
            colors.forEach((_, sizes) => sizes.removeWhere((_, q) => q == 0));
          });
          delta.removeWhere((_, colors) {
            colors.removeWhere((_, sizes) => sizes.isEmpty);
            return colors.isEmpty;
          });

          final Map<String, Map<String, dynamic>> productData = {};
          for (final productId in delta.keys) {
            final ref = _db.collection('products').doc(productId);
            final snap = await tx.get(ref);
            if (!snap.exists) {
              throw Exception('المنتج ($productId) غير موجود.');
            }
            productData[productId] = Map<String, dynamic>.from(snap.data()!);
          }

          // ---- writes ----
          for (final productId in delta.keys) {
            final ref = _db.collection('products').doc(productId);
            final data = productData[productId]!;
            final stock = Map<String, dynamic>.from(data['stock'] as Map? ?? {});

            for (final colorEntry in delta[productId]!.entries) {
              final color = colorEntry.key;
              final colorMap =
                  Map<String, dynamic>.from(stock[color] ?? <String, dynamic>{});
              for (final sizeEntry in colorEntry.value.entries) {
                final current = (colorMap[sizeEntry.key] as num?)?.toInt() ?? 0;
                final remaining = current - sizeEntry.value; // subtract delta
                if (remaining < 0) {
                  throw Exception(
                    'الكمية غير كافية للمنتج (${data['name']}) - $color - ${sizeEntry.key}.',
                  );
                }
                colorMap[sizeEntry.key] = remaining;
              }
              stock[color] = colorMap;
            }

            tx.update(ref, {
              'stock': stock,
              'updatedAt': DateTime.now().toIso8601String(),
            });
          }

          tx.set(orderRef, order.toMap());
        });
      }

      final index = orders.indexWhere((o) => o.id == order.id);
      if (index >= 0) {
        orders[index] = order;
      } else {
        orders.insert(0, order);
      }

      clearForm();
      emit(OrderSuccess('تم حفظ الطلب بنجاح.'));
    } catch (e) {
      emit(OrderError(e.toString()));
    }
  }

  // ---------------------------------------------------------------------
  // Status transitions
  // ---------------------------------------------------------------------

  Future<void> updateOrderStatus({
    required OrderModel order,
    required OrderStatus newStatus,
  }) async {
    emit(OrderFormLoadChanged());
    try {
      if (newStatus == OrderStatus.returned) {
        await _db.runTransaction((tx) async {
          final orderRef = _db.collection('orders').doc(order.id);

          // (1) read the order live inside the transaction — never trust the
          // in-memory `order`. This is what stops a duplicate/concurrent
          // "تعيين: مرتجع" tap (or a Firestore retry) from double-restocking.
          final orderSnap = await tx.get(orderRef);
          if (!orderSnap.exists) throw Exception('الطلب غير موجود.');

          final itemsRaw = List<Map<String, dynamic>>.from(
            (orderSnap.data()!['items'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map)),
          );

          // (2) aggregate quantities per product/color/size — but only for
          // items NOT already individually `returned` (those were restocked
          // once already by updateItemStatus; adding them again would
          // double-count).
          final Map<String, Map<String, Map<String, int>>> restockMap = {};
          for (final m in itemsRaw) {
            final itemStatus = ItemStatus.values.firstWhere(
              (s) => s.englishName == m['status'],
              orElse: () => ItemStatus.pending,
            );
            if (itemStatus == ItemStatus.returned) continue;
            final productId = m['productId'] as String;
            final color = m['color'] as String;
            final size = m['size'] as String;
            final quantity = (m['quantity'] as num).toInt();
            restockMap
                .putIfAbsent(productId, () => {})
                .putIfAbsent(color, () => {})
                .update(size, (v) => v + quantity, ifAbsent: () => quantity);
          }

          // (3) read each affected product once
          final Map<String, Map<String, dynamic>> productData = {};
          for (final productId in restockMap.keys) {
            final productRef = _db.collection('products').doc(productId);
            final productSnap = await tx.get(productRef);
            if (!productSnap.exists) {
              throw Exception('المنتج ($productId) غير موجود.');
            }
            productData[productId] = Map<String, dynamic>.from(productSnap.data()!);
          }

          // (4) apply all increments, single tx.update() per product
          for (final productId in restockMap.keys) {
            final productRef = _db.collection('products').doc(productId);
            final data = productData[productId]!;
            final stock = Map<String, dynamic>.from(data['stock'] as Map);

            for (final colorEntry in restockMap[productId]!.entries) {
              final color = colorEntry.key;
              final colorMap = Map<String, dynamic>.from(stock[color] ?? <String, dynamic>{});
              for (final sizeEntry in colorEntry.value.entries) {
                final current = (colorMap[sizeEntry.key] as num?)?.toInt() ?? 0;
                colorMap[sizeEntry.key] = current + sizeEntry.value;
              }
              stock[color] = colorMap;
            }

            tx.update(productRef, {
              'stock': stock,
              'updatedAt': DateTime.now().toIso8601String(),
            });
          }

          // (5) every item ends up `returned`, whether or not it was restocked
          // by this action, plus the order's own status.
          for (final m in itemsRaw) {
            m['status'] = ItemStatus.returned.englishName;
          }
          tx.update(orderRef, {
            'items': itemsRaw,
            'status': newStatus.englishName,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        });
      } else {
        await _db.collection('orders').doc(order.id).update({
          'status': newStatus.englishName,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }

      order.status = newStatus;
      if (newStatus == OrderStatus.returned) {
        for (final item in order.items) {
          item.status = ItemStatus.returned;
        }
      }
      emit(OrderSuccess('تم تحديث حالة الطلب.'));
      emit(OrderLoaded(orders));
    } catch (e) {
      emit(OrderError(e.toString()));
    }
  }

  /// Changes a single [OrderItem]'s status within [order], restocking only
  /// that one item's quantity when it transitions into `returned` from a
  /// non-`returned` status. All other items in the order are untouched, and
  /// the parent order's own `status` is left exactly as-is.
  Future<void> updateItemStatus({
    required OrderModel order,
    required String itemId,
    required ItemStatus newStatus,
  }) async {
    emit(OrderFormLoadChanged());
    try {
      await _db.runTransaction((tx) async {
        final orderRef = _db.collection('orders').doc(order.id);
        final orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) throw Exception('الطلب غير موجود.');

        final itemsRaw = List<Map<String, dynamic>>.from(
          (orderSnap.data()!['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map)),
        );
        final index = itemsRaw.indexWhere((m) => m['itemId'] == itemId);
        if (index == -1) throw Exception('العنصر غير موجود.');

        final currentStatus = ItemStatus.values.firstWhere(
          (s) => s.englishName == itemsRaw[index]['status'],
          orElse: () => ItemStatus.pending,
        );

        // Re-checked against the *live* document on every attempt (including
        // Firestore's own automatic transaction retries), not the possibly-
        // stale in-memory `order` passed into this method. This is what
        // actually prevents double-restocking under concurrent/duplicate calls.
        if (currentStatus == newStatus) return;

        final shouldRestock = newStatus == ItemStatus.returned &&
            currentStatus != ItemStatus.returned;

        if (shouldRestock) {
          final productId = itemsRaw[index]['productId'] as String;
          final color = itemsRaw[index]['color'] as String;
          final size = itemsRaw[index]['size'] as String;
          final quantity = (itemsRaw[index]['quantity'] as num).toInt();

          final productRef = _db.collection('products').doc(productId);
          final productSnap = await tx.get(productRef);
          if (!productSnap.exists) {
            throw Exception('المنتج ($productId) غير موجود.');
          }
          final stock = Map<String, dynamic>.from(
            (productSnap.data()!['stock'] as Map),
          );
          final colorMap =
              Map<String, dynamic>.from(stock[color] ?? <String, dynamic>{});
          final current = (colorMap[size] as num?)?.toInt() ?? 0;
          colorMap[size] = current + quantity;
          stock[color] = colorMap;

          tx.update(productRef, {
            'stock': stock,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }

        itemsRaw[index]['status'] = newStatus.englishName;
        tx.update(orderRef, {
          'items': itemsRaw,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      });

      final idx = order.items.indexWhere((i) => i.itemId == itemId);
      if (idx != -1) order.items[idx].status = newStatus;
      emit(OrderSuccess('تم تحديث حالة العنصر.'));
      emit(OrderLoaded(orders));
    } catch (e) {
      emit(OrderError(e.toString()));
    }
  }

  Future<void> updateOrderQrCode({
    required OrderModel order,
    required BuildContext context,
  }) async {
    emit(OrderFormLoadChanged());

    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (barcode != null) {
      final code = barcode.split('=').last;
      final orderRef = _db.collection('orders').doc(order.id);
      await orderRef.update({
        'qrCode': [code],
      });
      order.qrCode = [code];
    }

    emit(OrderFormChanged());
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Future<void> close() {
    customerNameCtrl.dispose();
    customerPhoneCtrl.dispose();
    addressCtrl.dispose();
    areaCtrl.dispose();
    streetCtrl.dispose();
    destinationCtrl.dispose();
    deliveryDateCtrl.dispose();
    qrCodeCtrl.dispose();
    return super.close();
  }
}
