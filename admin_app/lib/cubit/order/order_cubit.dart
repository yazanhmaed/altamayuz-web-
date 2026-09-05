import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:simple_barcode_scanner/simple_barcode_scanner.dart';

import '../../data/order/order_model.dart';
import '../../data/order/pick_result_model.dart';
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
    selectedItems.clear();
    emit(OrderFormChanged());
  }

  void loadOrderForEditing(OrderModel orderModel) {
    editingOrder = orderModel;
    customerNameCtrl.text = orderModel.customerName;
    customerPhoneCtrl.text = orderModel.customerPhone;
    addressCtrl.text = orderModel.address;
    areaCtrl.text = orderModel.area;
    streetCtrl.text = orderModel.street;
    destinationCtrl.text = orderModel.destination;
    deliveryDateCtrl.text = orderModel.deliveryDate;
    selectedItems
      ..clear()
      ..addAll(orderModel.items);
    emit(OrderFormChanged());
  }

  OrderModel _buildOrder({required String id}) {
    return OrderModel(
      id: id,
      customerName: customerNameCtrl.text.trim(),
      customerPhone: customerPhoneCtrl.text.trim(),
      destination: destinationCtrl.text.trim(),
      address: addressCtrl.text.trim(),
      area: areaCtrl.text.trim(),
      street: streetCtrl.text.trim(),
      items: List.of(selectedItems),
      qrCode: editingOrder?.qrCode ?? [],
      createdAt: editingOrder?.createdAt ?? DateTime.now(),
      status: editingOrder?.status ?? OrderStatus.pending,
      deliveryDate: deliveryDateCtrl.text.trim(),
      source: editingOrder?.source ?? 'manual',
    );
  }

  /// Creates a brand-new order, deducting stock immediately in a single
  /// transaction. Quantities are aggregated per product/color/size first so
  /// each product document only ever receives one `tx.update()` call — the
  /// same anti-clobber pattern used when restocking returns.
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
        await orderRef.set(order.toMap());
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
          // (1) aggregate quantities per product/color/size first
          final Map<String, Map<String, Map<String, int>>> restockMap = {};
          for (final item in order.items) {
            restockMap
                .putIfAbsent(item.productId, () => {})
                .putIfAbsent(item.color, () => {})
                .update(item.size, (v) => v + item.quantity, ifAbsent: () => item.quantity);
          }

          // (2) read each product once
          final Map<String, Map<String, dynamic>> productData = {};
          for (final productId in restockMap.keys) {
            final productRef = _db.collection('products').doc(productId);
            final productSnap = await tx.get(productRef);
            if (!productSnap.exists) {
              throw Exception('المنتج ($productId) غير موجود.');
            }
            productData[productId] = Map<String, dynamic>.from(productSnap.data()!);
          }

          // (3) apply all increments, single tx.update() per product
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

          // (4) update the order itself
          final orderRef = _db.collection('orders').doc(order.id);
          tx.update(orderRef, {
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
      emit(OrderSuccess('تم تحديث حالة الطلب.'));
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

    await SimpleBarcodeScanner.scanBarcode(
      context,
      barcodeAppBar: const BarcodeAppBar(
        appBarTitle: 'مسح QR',
        centerTitle: false,
        enableBackButton: true,
        backButtonIcon: Icon(Icons.arrow_back_ios),
      ),
      isShowFlashIcon: true,
      delayMillis: 500,
      cameraFace: CameraFace.back,
      scanFormat: ScanFormat.ONLY_QR_CODE,
    ).then((barcode) async {
      if (barcode == null) return;
      final code = barcode.split('=').last;
      final orderRef = _db.collection('orders').doc(order.id);
      await orderRef.update({
        'qrCode': [code],
      });
      order.qrCode = [code];
    });

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
    return super.close();
  }
}
