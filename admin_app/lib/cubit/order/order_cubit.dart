import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/customer/customer_stats.dart';
import '../../data/order/order_model.dart';
import '../../data/order/pick_result_model.dart';
import '../../data/product/product_model.dart';
import '../../screens/orders/widgets/qr_scanner_screen.dart';
import '../../utils/arabic_digits.dart';
import '../../utils/jordan_phone.dart';
import '../../utils/promotion_pricing.dart' show roundMoney;
import 'order_state.dart';

enum OrderFilter { active, all, pending, shipped, completed, returned }

/// Thrown inside the order transaction when a variant has less live stock
/// than the order needs. Aborts the whole transaction (no partial deduction).
class StockShortageException implements Exception {
  final String name;
  final String color;
  final String size;
  final int available;
  const StockShortageException({
    required this.name,
    required this.color,
    required this.size,
    required this.available,
  });

  String get message => 'المقاس $size ($color) من «$name» متوفر منه $available فقط';

  @override
  String toString() => message;
}

class OrderCubit extends Cubit<OrderState> {
  OrderCubit() : super(OrderInitial());

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<OrderModel> orders = [];
  bool _hasFetched = false;
  OrderFilter currentFilter = OrderFilter.active;

  // ---- create/edit order form state ----
  final customerNameCtrl = TextEditingController();
  final customerPhoneCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final areaCtrl = TextEditingController();
  final streetCtrl = TextEditingController();
  final discountNoteCtrl = TextEditingController();
  final destinationCtrl = TextEditingController();
  final deliveryDateCtrl = TextEditingController();
  final qrCodeCtrl = TextEditingController();
  final List<OrderItem> selectedItems = [];
  OrderModel? editingOrder;

  // ---- "قيمة الطلب" (order value) ----
  /// Holds the order's final `total`. AUTO by default: follows
  /// [computedOrderValue] as items change. Once the owner types in it, it
  /// switches to MANUAL ([orderValueManual]) until [resetOrderValue].
  final orderValueCtrl = TextEditingController();
  bool orderValueManual = false;

  /// Sum of the items' `unitPrice × quantity` (items without a price, from
  /// older manual orders, count as 0). Saved as the order's `subtotal`.
  double get itemsSubtotal => roundMoney(selectedItems.fold<double>(
      0, (acc, i) => acc + (i.unitPrice ?? 0) * i.quantity));

  bool get hasPricedItems => selectedItems.any((i) => i.unitPrice != null);

  int _qtyIn(Iterable<OrderItem> items, String productId, String color, String size) =>
      items
          .where((i) => i.productId == productId && i.color == color && i.size == size)
          .fold<int>(0, (n, i) => n + i.quantity);

  /// Most units of this variant the order may hold in total: the live stock,
  /// plus — when editing — what this order already took (deducted at save).
  int maxForVariant(ProductModel product, String color, String size) {
    final live = product.stock[color]?[size] ?? 0;
    final held = editingOrder == null
        ? 0
        : _qtyIn(editingOrder!.items, product.id, color, size);
    final max = live + held;
    return max < 0 ? 0 : max;
  }

  /// How many more units of this variant can still be added to the order
  /// (across all its lines).
  int remainingFor(ProductModel product, String color, String size) {
    final r = maxForVariant(product, color, size) -
        _qtyIn(selectedItems, product.id, color, size);
    return r < 0 ? 0 : r;
  }

  /// Trims lines that ask for more than the live stock now allows (newest
  /// lines first; a line that reaches 0 is removed). Returns one warning per
  /// changed variant, empty when nothing changed. Products missing from
  /// [products] are left alone.
  List<String> reconcileWithStock(List<ProductModel> products) {
    final byId = {for (final p in products) p.id: p};
    final warnings = <String>[];
    final seen = <String>{};
    for (final line in List.of(selectedItems)) {
      final key = '${line.productId}|${line.color}|${line.size}';
      if (!seen.add(key)) continue;
      final product = byId[line.productId];
      if (product == null) continue;
      final max = maxForVariant(product, line.color, line.size);
      var excess = _qtyIn(selectedItems, line.productId, line.color, line.size) - max;
      if (excess <= 0) continue;
      for (var i = selectedItems.length - 1; i >= 0 && excess > 0; i--) {
        final it = selectedItems[i];
        if (it.productId != line.productId || it.color != line.color || it.size != line.size) {
          continue;
        }
        final cut = excess < it.quantity ? excess : it.quantity;
        excess -= cut;
        if (cut == it.quantity) {
          selectedItems.removeAt(i);
        } else {
          selectedItems[i] = it.copyWith(quantity: it.quantity - cut);
        }
      }
      warnings.add(max == 0
          ? 'أُزيل «${product.name}» ${line.size} (${line.color}): نفد من المخزون'
          : 'خُفّضت كمية «${product.name}» ${line.size} (${line.color}) إلى $max حسب المخزون');
    }
    if (warnings.isNotEmpty) {
      if (selectedItems.isNotEmpty && !selectedItems.any((i) => i.isPrimary)) {
        selectedItems[0] = selectedItems[0].copyWith(isPrimary: true);
      }
      _syncOrderValue();
      emit(OrderFormChanged());
    }
    return warnings;
  }

  /// The automatic order value: items subtotal minus any existing cart
  /// discount (only storefront orders have one), never below 0.
  double get computedOrderValue {
    final v = itemsSubtotal - (editingOrder?.cartDiscountAmount ?? 0);
    return v < 0 ? 0 : roundMoney(v);
  }

  /// The typed order value, or null when the field is empty/unparseable.
  double? get enteredOrderValue {
    final t = normalizeDigits(orderValueCtrl.text.trim()).replaceAll('٫', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  /// Appended to `discountNote` when the saved total differs from the
  /// computed one, so reports and the order details explain the gap.
  static final _manualValueNote =
      RegExp(r'(\s·\s)?قيمة مُعدّلة يدوياً: [\d.]+ بدل [\d.]+');

  void _syncOrderValue() {
    if (orderValueManual) return;
    orderValueCtrl.text =
        hasPricedItems ? computedOrderValue.toStringAsFixed(2) : '';
  }

  /// Called from the field's onChanged (user edits only).
  void onOrderValueEdited() {
    if (orderValueManual) return;
    orderValueManual = true;
    emit(OrderFormChanged());
  }

  void resetOrderValue() {
    orderValueManual = false;
    _syncOrderValue();
    emit(OrderFormChanged());
  }

  /// "العميل وافق على تلقي العروض" switch on the new-order form. Only for
  /// when the customer agreed verbally; OFF never revokes an earlier consent.
  bool marketingConsent = false;

  void setMarketingConsent(bool value) {
    marketingConsent = value;
    emit(OrderFormChanged());
  }

  /// Fetches orders server-side filtered by [filter] (defaults to whatever
  /// [currentFilter] currently is). Every filter but [OrderFilter.all] is a
  /// naturally small/bounded set (active orders, or a single status) that
  /// the owner keeps moving orders out of — no `.limit()` needed there.
  /// `OrderFilter.all` is the one genuinely unbounded case, so it's the only
  /// one capped, at the 100 most recent orders across every status.
  Future<void> fetchOrders({OrderFilter? filter, bool refresh = false}) async {
    final targetFilter = filter ?? currentFilter;
    if (currentFilter == targetFilter && _hasFetched && !refresh) {
      emit(OrderLoaded(orders));
      return;
    }
    currentFilter = targetFilter;
    emit(OrderLoading());
    try {
      Query query = _db.collection('orders').orderBy('createdAt', descending: true);
      switch (targetFilter) {
        case OrderFilter.active:
          query = query.where('status', whereIn: ['pending', 'shipped']);
        case OrderFilter.all:
          query = query.limit(100);
        case OrderFilter.pending:
        case OrderFilter.shipped:
        case OrderFilter.completed:
        case OrderFilter.returned:
          query = query.where('status', isEqualTo: targetFilter.name);
      }
      final snap = await query.get();
      orders = snap.docs
          .map((d) => OrderModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      _hasFetched = true;
      emit(OrderLoaded(orders));
    } catch (e) {
      emit(OrderError(e.toString()));
    }
  }

  // ---------------------------------------------------------------------
  // Create/edit order form
  // ---------------------------------------------------------------------

  /// [unitPrice] defaults (in the picker) to the product's effective price
  /// — sale price or running promotion, shared rule — and the owner may edit
  /// it. [promoId]/[promoName] are set only when that promotion price was kept.
  void addItem(
    PickResult pick,
    int quantity, {
    double? unitPrice,
    double? originalPrice,
    String? promoId,
    String? promoName,
  }) {
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
        unitPrice: unitPrice,
        originalPrice: originalPrice,
        promoId: promoId,
        promoName: promoName,
      ),
    );
    _syncOrderValue();
    emit(OrderFormChanged());
  }

  void removeItem(int index) {
    if (index < 0 || index >= selectedItems.length) return;
    selectedItems.removeAt(index);
    _syncOrderValue();
    emit(OrderFormChanged());
  }

  void clearForm() {
    editingOrder = null;
    customerNameCtrl.clear();
    customerPhoneCtrl.clear();
    addressCtrl.clear();
    areaCtrl.clear();
    streetCtrl.clear();
    discountNoteCtrl.clear();
    destinationCtrl.clear();
    deliveryDateCtrl.clear();
    qrCodeCtrl.clear();
    selectedItems.clear();
    marketingConsent = false;
    orderValueManual = false;
    orderValueCtrl.clear();
    emit(OrderFormChanged());
  }

  void loadOrderForEditing(OrderModel orderModel) {
    editingOrder = orderModel;
    customerNameCtrl.text = orderModel.customerName;
    customerPhoneCtrl.text = jordanPhoneToLocal(orderModel.customerPhone);
    addressCtrl.text = orderModel.address;
    areaCtrl.text = orderModel.area;
    streetCtrl.text = orderModel.street;
    // The manual-value note is regenerated on save; don't show it as text.
    discountNoteCtrl.text =
        orderModel.discountNote.replaceAll(_manualValueNote, '').trim();
    destinationCtrl.text = orderModel.destination;
    deliveryDateCtrl.text = orderModel.deliveryDate;
    qrCodeCtrl.text = orderModel.qrCode.isNotEmpty ? orderModel.qrCode.first : '';
    selectedItems
      ..clear()
      ..addAll(orderModel.items);
    final total = orderModel.total;
    orderValueManual =
        total != null && roundMoney(total) != computedOrderValue;
    if (orderValueManual) {
      orderValueCtrl.text = total!.toStringAsFixed(2);
    } else {
      orderValueCtrl.clear();
      _syncOrderValue();
    }
    emit(OrderFormChanged());
  }

  OrderModel _buildOrder({required String id}) {
    // Order value: `total` = the field; `subtotal` = the items sum. A manual
    // value that differs from the computed one is explained in discountNote.
    final entered = enteredOrderValue;
    final total = entered == null ? editingOrder?.total : roundMoney(entered);
    final computed = computedOrderValue;
    var note = discountNoteCtrl.text.trim().replaceAll(_manualValueNote, '').trim();
    if (orderValueManual && total != null && total != computed) {
      final manual =
          'قيمة مُعدّلة يدوياً: ${total.toStringAsFixed(2)} بدل ${computed.toStringAsFixed(2)}';
      note = note.isEmpty ? manual : '$note · $manual';
    }
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
      discountNote: note,
      items: List.of(selectedItems),
      qrCode: qrCodeCtrl.text.trim().isNotEmpty
          ? [qrCodeCtrl.text.trim()]
          : (editingOrder?.qrCode ?? []),
      createdAt: editingOrder?.createdAt ?? DateTime.now(),
      status: editingOrder?.status ?? OrderStatus.pending,
      deliveryDate: deliveryDateCtrl.text.trim(),
      source: editingOrder?.source ?? 'manual',
      // Cart-discount fields stay as the storefront wrote them. subtotal/total
      // come from the items and the "قيمة الطلب" field (unchanged when the
      // items carry no prices and the field is empty, e.g. old manual orders).
      subtotal: hasPricedItems ? itemsSubtotal : editingOrder?.subtotal,
      cartDiscountAmount: editingOrder?.cartDiscountAmount,
      cartDiscountTierMinQuantity: editingOrder?.cartDiscountTierMinQuantity,
      total: total,
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
    final value = enteredOrderValue;
    final valueRequired = hasPricedItems || orderValueCtrl.text.trim().isNotEmpty;
    if (valueRequired && (value == null || value <= 0)) {
      emit(OrderError('أدخل قيمة طلب صحيحة أكبر من صفر.'));
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

          // Customer read goes last: every read must happen before any write.
          final customerPhone = normalizePhoneE164(order.customerPhone);
          final customerRef = customerPhone == null
              ? null
              : _db.collection('customers').doc(customerPhone);
          final customerSnap =
              customerRef == null ? null : await tx.get(customerRef);

          // Validate every variant against the live stock BEFORE any write,
          // then write. Any shortage aborts the whole transaction.
          final Map<String, Map<String, dynamic>> newStock = {};
          for (final productId in need.keys) {
            final data = productData[productId]!;
            final stock = Map<String, dynamic>.from(data['stock'] as Map? ?? {});

            for (final colorEntry in need[productId]!.entries) {
              final color = colorEntry.key;
              final colorMap = Map<String, dynamic>.from(stock[color] ?? <String, dynamic>{});
              for (final sizeEntry in colorEntry.value.entries) {
                final current = (colorMap[sizeEntry.key] as num?)?.toInt() ?? 0;
                final remaining = current - sizeEntry.value;
                if (remaining < 0) {
                  throw StockShortageException(
                    name: '${data['name'] ?? productId}',
                    color: color,
                    size: sizeEntry.key,
                    available: current < 0 ? 0 : current,
                  );
                }
                colorMap[sizeEntry.key] = remaining;
              }
              stock[color] = colorMap;
            }
            newStock[productId] = stock;
          }

          for (final entry in newStock.entries) {
            tx.update(_db.collection('products').doc(entry.key), {
              'stock': entry.value,
              'updatedAt': DateTime.now().toIso8601String(),
            });
          }

          tx.set(orderRef, order.toMap());

          if (customerRef != null) {
            _upsertCustomer(
              tx,
              customerRef,
              exists: customerSnap!.exists,
              order: order,
              phone: customerPhone!,
              marketingConsent: marketingConsent,
            );
          }
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
          final storedData = orderSnap.data()!;
          final storedOrder = OrderModel.fromMap(storedData);
          final newData = order.toMap();

          // Customer delivery stats follow the edit too. Only when the phone
          // is unchanged; a moved order is left for the recompute tool.
          final customerRef = customerRefForOrder(_db, storedData);
          final sameCustomer =
              customerRef?.path == customerRefForOrder(_db, newData)?.path;
          final customerSnap = (customerRef != null && sameCustomer)
              ? await tx.get(customerRef)
              : null;

          // A returned order already gave its stock back; leave inventory
          // untouched and just persist the edited fields.
          if (storedOrder.status == OrderStatus.returned) {
            tx.set(orderRef, newData);
            applyCustomerStatsChange(tx, customerSnap,
                before: storedData, after: newData);
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
                  final held = storedOrder.items
                      .where((i) =>
                          i.productId == productId &&
                          i.color == color &&
                          i.size == sizeEntry.key)
                      .fold<int>(0, (n, i) => n + i.quantity);
                  final available = current + held;
                  throw StockShortageException(
                    name: '${data['name'] ?? productId}',
                    color: color,
                    size: sizeEntry.key,
                    available: available < 0 ? 0 : available,
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

          tx.set(orderRef, newData);
          applyCustomerStatsChange(tx, customerSnap,
              before: storedData, after: newData);
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
    } on StockShortageException catch (e) {
      // The form (and its items) is kept so the owner can adjust.
      emit(OrderError(e.message, isStockShortage: true));
    } catch (e) {
      emit(OrderError(e.toString()));
    }
  }

  /// Same rules as the storefront's submitPublicOrder: create with counters at
  /// 1, or bump counters and refresh name/address. Consent is only ever turned
  /// ON here, never off. Manual orders have no stored total, so they add 0 to
  /// `totalOrdersValue`.
  void _upsertCustomer(
    Transaction tx,
    DocumentReference<Map<String, dynamic>> ref, {
    required bool exists,
    required OrderModel order,
    required String phone,
    required bool marketingConsent,
  }) {
    final now = FieldValue.serverTimestamp();
    final value = order.total ?? 0;
    if (!exists) {
      tx.set(ref, {
        'name': order.customerName,
        'phone': phone,
        'city': order.address,
        'area': order.area,
        'street': order.street,
        'firstOrderAt': now,
        'lastOrderAt': now,
        'ordersCount': 1,
        'totalOrdersValue': value,
        'marketingConsent': marketingConsent,
        'consentUpdatedAt': marketingConsent ? now : null,
        'notes': '',
        'tags': <String>[],
        'source': 'manual',
        'createdAt': now,
        'updatedAt': now,
      });
    } else {
      tx.update(ref, {
        'name': order.customerName,
        'city': order.address,
        'area': order.area,
        'street': order.street,
        'lastOrderAt': now,
        'ordersCount': FieldValue.increment(1),
        'totalOrdersValue': FieldValue.increment(value),
        'updatedAt': now,
        if (marketingConsent) ...{
          'marketingConsent': true,
          'consentUpdatedAt': now,
        },
      });
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
          final orderData = orderSnap.data()!;

          final itemsRaw = List<Map<String, dynamic>>.from(
            (orderData['items'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map)),
          );

          // Customer read with the other reads (before any write).
          final customerRef = customerRefForOrder(_db, orderData);
          final customerSnap =
              customerRef == null ? null : await tx.get(customerRef);

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
          applyCustomerStatsChange(tx, customerSnap, before: orderData, after: {
            ...orderData,
            'items': itemsRaw,
            'status': newStatus.englishName,
          });
        });
      } else {
        // A transaction (not a bare update) so the customer's delivery stats
        // move with the status, e.g. `completed` counts pending items as
        // delivered. Before/after come from the live order, so repeats are
        // no-ops for the stats.
        await _db.runTransaction((tx) async {
          final orderRef = _db.collection('orders').doc(order.id);
          final orderSnap = await tx.get(orderRef);
          if (!orderSnap.exists) throw Exception('الطلب غير موجود.');
          final orderData = orderSnap.data()!;
          final customerRef = customerRefForOrder(_db, orderData);
          final customerSnap =
              customerRef == null ? null : await tx.get(customerRef);

          tx.update(orderRef, {
            'status': newStatus.englishName,
            'updatedAt': DateTime.now().toIso8601String(),
          });
          applyCustomerStatsChange(tx, customerSnap, before: orderData, after: {
            ...orderData,
            'status': newStatus.englishName,
          });
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
        final orderData = orderSnap.data()!;

        final itemsRaw = List<Map<String, dynamic>>.from(
          (orderData['items'] as List)
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

        // Customer read before any write (the product read below too).
        final customerRef = customerRefForOrder(_db, orderData);
        final customerSnap =
            customerRef == null ? null : await tx.get(customerRef);

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
        applyCustomerStatsChange(tx, customerSnap,
            before: orderData, after: {...orderData, 'items': itemsRaw});
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
    discountNoteCtrl.dispose();
    destinationCtrl.dispose();
    deliveryDateCtrl.dispose();
    qrCodeCtrl.dispose();
    orderValueCtrl.dispose();
    return super.close();
  }
}
