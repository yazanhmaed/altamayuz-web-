import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/customer/customer_stats.dart';
import '../../data/order/order_model.dart';
import '../../data/order/pick_result_model.dart';
import '../../data/product/product_model.dart';
import '../../screens/orders/widgets/qr_scanner_screen.dart';
import '../../utils/arabic_digits.dart';
import '../../utils/cart_discount.dart';
import '../../utils/jordan_phone.dart';
import '../../utils/order_search.dart';
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

  String get message =>
      'المقاس $size ($color) من «$name» متوفر منه $available فقط';

  @override
  String toString() => message;
}

/// Readable reason the order-edit transaction was aborted.
class OrderEditException implements Exception {
  final String message;
  const OrderEditException(this.message);

  @override
  String toString() => message;
}

/// A Firestore value as a comparable string (map keys sorted, timestamps
/// exact), so two reads of an unchanged document compare equal.
String _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return '{${keys.map((k) => '$k:${_canonical(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(_canonical).join(',')}]';
  if (v is Timestamp) return 'ts${v.seconds}.${v.nanoseconds}';
  return '$v';
}

String _itemsSignature(List<OrderItem> items) => items
    .map((i) =>
        '${i.productId}|${i.color}|${i.size}|${i.quantity}|${i.unitPrice}')
    .join(';');

/// Order fields the edit form may change (besides items and money).
const _editableOrderFields = [
  'customerName',
  'customerPhone',
  'address',
  'area',
  'street',
  'discountNote',
  'destination',
  'deliveryDate',
  'qrCode',
  'total',
];

class OrderCubit extends Cubit<OrderState> {
  OrderCubit() : super(OrderInitial());

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<OrderModel> orders = [];
  bool _hasFetched = false;
  OrderFilter currentFilter = OrderFilter.active;

  /// Page size of the only capped filter ([OrderFilter.all]).
  static const _allPageSize = 100;
  DocumentSnapshot? _lastAllDoc;

  /// More orders exist on the server for the current filter ("الكل" only;
  /// the other filters load their whole, bounded set).
  bool hasMoreOrders = false;

  /// Local search over the loaded [orders] (never queries Firestore). Kept
  /// across filter changes.
  String searchQuery = '';

  bool get isSearching => searchQuery.trim().isNotEmpty;

  /// [orders] narrowed by [searchQuery]; the source list is never mutated.
  List<OrderModel> get visibleOrders => isSearching
      ? orders.where((o) => orderMatchesSearch(o, searchQuery)).toList()
      : orders;

  void setSearchQuery(String query) {
    if (query == searchQuery) return;
    searchQuery = query;
    // While a fetch runs the list shows its spinner; it re-filters on load.
    if (state is! OrderLoading) emit(OrderLoaded(orders));
  }

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

  /// Raw order document the edit form was loaded from; the save aborts if the
  /// live document no longer matches it.
  Map<String, dynamic>? _editBase;

  /// Cart-discount tiers, loaded when editing a storefront order whose items
  /// may change (null = keep the stored discount).
  List<CartDiscountTier>? _cartTiers;

  /// Form signature right after [loadOrderForEditing], for [isDirty].
  String _initialSignature = '';

  /// True while [submitOrder] runs; repeated taps are ignored.
  bool saving = false;

  /// Items may be changed: always on a new order; on an edit only while every
  /// item is pending and the order isn't finalized.
  bool get itemsEditable => editingOrder?.itemsEditable ?? true;

  bool get _itemsChanged =>
      editingOrder != null &&
      _itemsSignature(selectedItems) != _itemsSignature(editingOrder!.items);

  String _formSignature() => [
        customerNameCtrl.text.trim(),
        normalizePhoneE164(customerPhoneCtrl.text) ??
            customerPhoneCtrl.text.trim(),
        addressCtrl.text.trim(),
        areaCtrl.text.trim(),
        streetCtrl.text.trim(),
        discountNoteCtrl.text.trim(),
        destinationCtrl.text.trim(),
        deliveryDateCtrl.text.trim(),
        qrCodeCtrl.text.trim(),
        _itemsSignature(selectedItems),
        orderValueCtrl.text.trim(),
      ].join('\u0001');

  /// Edit form differs from the loaded order (always true for a new order).
  bool get isDirty =>
      editingOrder == null || _formSignature() != _initialSignature;

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

  int _qtyIn(Iterable<OrderItem> items, String productId, String color,
          String size) =>
      items
          .where((i) =>
              i.productId == productId && i.color == color && i.size == size)
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
    // Locked items (delivered/returned order) are never touched.
    if (!itemsEditable) return const [];
    final byId = {for (final p in products) p.id: p};
    final warnings = <String>[];
    final seen = <String>{};
    for (final line in List.of(selectedItems)) {
      final key = '${line.productId}|${line.color}|${line.size}';
      if (!seen.add(key)) continue;
      final product = byId[line.productId];
      if (product == null) continue;
      final max = maxForVariant(product, line.color, line.size);
      var excess =
          _qtyIn(selectedItems, line.productId, line.color, line.size) - max;
      if (excess <= 0) continue;
      for (var i = selectedItems.length - 1; i >= 0 && excess > 0; i--) {
        final it = selectedItems[i];
        if (it.productId != line.productId ||
            it.color != line.color ||
            it.size != line.size) {
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

  /// A storefront order whose items were edited gets the cart tiers
  /// re-applied with the same function as checkout. Null = keep the stored
  /// discount (items unchanged, manual order, or tiers not loaded).
  CartDiscountResult? get _reappliedCartDiscount {
    final tiers = _cartTiers;
    if (tiers == null ||
        editingOrder?.source != 'storefront' ||
        !_itemsChanged) {
      return null;
    }
    return computeCartDiscount(
      tiers: tiers,
      totalQuantity: selectedItems.fold<int>(0, (n, i) => n + i.quantity),
      subtotal: itemsSubtotal,
    );
  }

  /// Cart-wide discount taken off [itemsSubtotal] (storefront orders only).
  double get cartDiscountAmount => roundMoney(
      _reappliedCartDiscount?.amount ?? editingOrder?.cartDiscountAmount ?? 0);

  /// The automatic order value: items subtotal minus the cart discount (only
  /// storefront orders have one), never below 0.
  double get computedOrderValue {
    final v = itemsSubtotal - cartDiscountAmount;
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
      Query query =
          _db.collection('orders').orderBy('createdAt', descending: true);
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
      _lastAllDoc = snap.docs.isEmpty ? null : snap.docs.last;
      hasMoreOrders =
          targetFilter == OrderFilter.all && snap.docs.length == _allPageSize;
      _hasFetched = true;
      emit(OrderLoaded(orders));
    } catch (e) {
      emit(OrderError(e.toString()));
    }
  }

  bool _loadingMore = false;

  /// Next page of the "الكل" list (100 more, by `createdAt` desc), appended
  /// to [orders]; the search re-applies through [visibleOrders].
  Future<void> loadMoreOrders() async {
    if (_loadingMore || !hasMoreOrders || _lastAllDoc == null) return;
    _loadingMore = true;
    final cursor = _lastAllDoc!;
    try {
      final snap = await _db
          .collection('orders')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(cursor)
          .limit(_allPageSize)
          .get();
      // The list was refetched or the filter changed meanwhile: drop it.
      if (currentFilter != OrderFilter.all || _lastAllDoc != cursor) return;
      final known = orders.map((o) => o.id).toSet();
      orders.addAll(snap.docs
          .map((d) => OrderModel.fromMap(d.data()))
          .where((o) => !known.contains(o.id)));
      if (snap.docs.isNotEmpty) _lastAllDoc = snap.docs.last;
      hasMoreOrders = snap.docs.length == _allPageSize;
      emit(OrderLoaded(orders));
    } catch (e) {
      emit(OrderError(e.toString()));
    } finally {
      _loadingMore = false;
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

  /// Replaces line [index] (product, color, size, quantity or price changed),
  /// keeping its id and primary flag.
  void replaceItem(
    int index,
    PickResult pick,
    int quantity, {
    double? unitPrice,
    double? originalPrice,
    String? promoId,
    String? promoName,
  }) {
    if (index < 0 || index >= selectedItems.length) return;
    final old = selectedItems[index];
    selectedItems[index] = OrderItem(
      itemId: old.itemId,
      productId: pick.productId,
      productName: pick.productName,
      color: pick.color,
      size: pick.size,
      sku: pick.sku,
      quantity: quantity,
      qrCode: old.qrCode,
      isPrimary: old.isPrimary,
      unitPrice: unitPrice,
      originalPrice: originalPrice,
      promoId: promoId,
      promoName: promoName,
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
    _editBase = null;
    _cartTiers = null;
    _initialSignature = '';
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
    qrCodeCtrl.text =
        orderModel.qrCode.isNotEmpty ? orderModel.qrCode.first : '';
    selectedItems
      ..clear()
      ..addAll(orderModel.items);
    final total = orderModel.total;
    orderValueManual = total != null && roundMoney(total) != computedOrderValue;
    if (orderValueManual) {
      orderValueCtrl.text = total!.toStringAsFixed(2);
    } else {
      orderValueCtrl.clear();
      _syncOrderValue();
    }
    _initialSignature = _formSignature();
    emit(OrderFormChanged());
  }

  /// Opens [order] in the edit form from a FRESH read of its document (the
  /// in-memory copy may be stale), and refreshes the list with it. For a
  /// storefront order with editable items, also loads the cart tiers so they
  /// can be re-applied. Throws when the order can't be read.
  Future<void> startEditing(OrderModel order) async {
    final snap = await _db.collection('orders').doc(order.id).get();
    if (!snap.exists) throw const OrderEditException('الطلب غير موجود.');
    final data = snap.data()!;
    final fresh = OrderModel.fromMap(data);

    List<CartDiscountTier>? tiers;
    if (fresh.source == 'storefront' && fresh.itemsEditable) {
      try {
        final t =
            await _db.collection('settings').doc('cartDiscountTiers').get();
        tiers = sanitizeCartDiscountTiers(t.data()?['tiers']);
      } catch (_) {
        // Keep the stored discount when the tiers can't be read.
      }
    }

    final i = orders.indexWhere((o) => o.id == fresh.id);
    if (i >= 0) orders[i] = fresh;
    loadOrderForEditing(fresh);
    _editBase = data;
    _cartTiers = tiers;
  }

  OrderModel _buildOrder({required String id}) {
    // Order value: `total` = the field; `subtotal` = the items sum. A manual
    // value that differs from the computed one is explained in discountNote.
    final entered = enteredOrderValue;
    final total = entered == null ? editingOrder?.total : roundMoney(entered);
    final computed = computedOrderValue;
    final reapplied = _reappliedCartDiscount;
    var note =
        discountNoteCtrl.text.trim().replaceAll(_manualValueNote, '').trim();
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
      cartDiscountAmount: reapplied != null
          ? roundMoney(reapplied.amount)
          : editingOrder?.cartDiscountAmount,
      cartDiscountTierMinQuantity: reapplied != null
          ? reapplied.tier?.minQuantity
          : editingOrder?.cartDiscountTierMinQuantity,
      total: total,
      updatedAt: editingOrder?.updatedAt,
      updatedBy: editingOrder?.updatedBy,
      editHistory: editingOrder?.editHistory ?? const [],
    );
  }

  /// Saves an order and keeps inventory in sync in a single transaction:
  /// a new order deducts every ordered unit; an edited order moves only the
  /// net delta vs. what was previously stored. Quantities are aggregated per
  /// product/color/size first so each product document only ever receives one
  /// `tx.update()` call — the same anti-clobber pattern used when restocking
  /// returns.
  Future<void> submitOrder() async {
    if (saving) return;
    if (customerNameCtrl.text.trim().isEmpty ||
        customerPhoneCtrl.text.trim().isEmpty) {
      emit(OrderError('اسم الزبون ورقم الهاتف مطلوبان.'));
      return;
    }
    if (selectedItems.isEmpty) {
      emit(OrderError('أضف قطعة واحدة على الأقل للطلب.'));
      return;
    }
    final value = enteredOrderValue;
    final valueRequired =
        hasPricedItems || orderValueCtrl.text.trim().isNotEmpty;
    if (valueRequired && (value == null || value <= 0)) {
      emit(OrderError('أدخل قيمة طلب صحيحة أكبر من صفر.'));
      return;
    }

    saving = true;
    emit(OrderFormLoadChanged());
    try {
      final isNewOrder = editingOrder == null;
      final orderRef = isNewOrder
          ? _db.collection('orders').doc()
          : _db.collection('orders').doc(editingOrder!.id);
      final order = _buildOrder(id: orderRef.id);

      if (isNewOrder) {
        await _db.runTransaction((tx) async {
          final Map<String, Map<String, Map<String, int>>> need = {};
          for (final item in order.items) {
            need
                .putIfAbsent(item.productId, () => {})
                .putIfAbsent(item.color, () => {})
                .update(item.size, (v) => v + item.quantity,
                    ifAbsent: () => item.quantity);
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
            final stock =
                Map<String, dynamic>.from(data['stock'] as Map? ?? {});

            for (final colorEntry in need[productId]!.entries) {
              final color = colorEntry.key;
              final colorMap = Map<String, dynamic>.from(
                  stock[color] ?? <String, dynamic>{});
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
        final saved = await _saveEdit(orderRef, order);
        final index = orders.indexWhere((o) => o.id == saved.id);
        if (index >= 0) orders[index] = saved;
        saving = false;
        clearForm();
        emit(OrderSuccess('تم تعديل الطلب'));
        return;
      }

      orders.insert(0, order);
      saving = false;
      clearForm();
      emit(OrderSuccess('تم حفظ الطلب بنجاح.'));
    } on StockShortageException catch (e) {
      // The form (and its items) is kept so the owner can adjust.
      saving = false;
      emit(OrderError(e.message, isStockShortage: true));
    } catch (e) {
      saving = false;
      emit(OrderError(e.toString()));
    }
  }

  /// Saves the owner's edit of an existing order in ONE transaction and
  /// returns the saved order.
  ///
  /// Reads (all before any write): the order — aborted if it changed since
  /// the form was opened —, every product whose stock moves, and the old/new
  /// customer. Writes: one `tx.update()` per product with the NET stock delta
  /// vs. the stored items (deduct where quantities grew, restore where they
  /// shrank; the same anti-clobber pattern as order creation and returns),
  /// the order, and the customer counters. Items only change while all of
  /// them are pending, so stock is never touched for a delivered/returned
  /// order. Do NOT "simplify" this into a bare set(): inventory would desync.
  Future<OrderModel> _saveEdit(
    DocumentReference<Map<String, dynamic>> orderRef,
    OrderModel order,
  ) async {
    final base = _editBase;
    if (base == null)
      throw const OrderEditException('تم تغيير الطلب، أعد فتحه');
    late OrderModel saved;

    await _db.runTransaction((tx) async {
      // ---- reads ----
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) throw const OrderEditException('الطلب غير موجود.');
      final live = orderSnap.data()!;
      // Another device, a status/item action or a QR scan changed the order
      // after the form was opened: never overwrite it.
      if (_canonical(live) != _canonical(base)) {
        throw const OrderEditException('تم تغيير الطلب، أعد فتحه');
      }
      final stored = OrderModel.fromMap(live);
      final itemsChanged =
          _itemsSignature(order.items) != _itemsSignature(stored.items);
      if (itemsChanged && !stored.itemsEditable) {
        throw const OrderEditException(
            'لا يمكن تعديل الأصناف بعد التسليم أو الإرجاع');
      }

      // net delta: + units to deduct, - units to restore.
      final Map<String, Map<String, Map<String, int>>> delta = {};
      if (itemsChanged) {
        void bump(String p, String c, String sz, int q) {
          delta
              .putIfAbsent(p, () => {})
              .putIfAbsent(c, () => {})
              .update(sz, (v) => v + q, ifAbsent: () => q);
        }

        for (final item in stored.items) {
          bump(item.productId, item.color, item.size, -item.quantity);
        }
        for (final item in order.items) {
          bump(item.productId, item.color, item.size, item.quantity);
        }
        delta.removeWhere((_, colors) {
          colors.removeWhere((_, sizes) {
            sizes.removeWhere((_, q) => q == 0);
            return sizes.isEmpty;
          });
          return colors.isEmpty;
        });
      }

      final productSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final productId in delta.keys) {
        productSnaps[productId] =
            await tx.get(_db.collection('products').doc(productId));
      }

      final oldPhone = normalizePhoneE164(stored.customerPhone);
      final newPhone = normalizePhoneE164(order.customerPhone);
      final oldRef =
          oldPhone == null ? null : _db.collection('customers').doc(oldPhone);
      final newRef =
          newPhone == null ? null : _db.collection('customers').doc(newPhone);
      final oldSnap = oldRef == null ? null : await tx.get(oldRef);
      final newSnap = newPhone == oldPhone
          ? oldSnap
          : (newRef == null ? null : await tx.get(newRef));

      // ---- validate stock against the live documents (before any write) ----
      final Map<String, Map<String, dynamic>> newStock = {};
      for (final productId in delta.keys) {
        final snap = productSnaps[productId]!;
        final changes = delta[productId]!;
        if (!snap.exists) {
          // A deleted product's line may only be removed or reduced; its
          // units have nowhere to go back to.
          final name = [...stored.items, ...order.items]
                  .firstWhere((i) => i.productId == productId)
                  .productName ??
              productId;
          if (changes.values.any((sizes) => sizes.values.any((q) => q > 0))) {
            throw OrderEditException(
                'المنتج «$name» محذوف؛ يمكن حذف سطره فقط.');
          }
          continue;
        }
        final data = snap.data()!;
        final name = '${data['name'] ?? productId}';
        final stock = Map<String, dynamic>.from(data['stock'] as Map? ?? {});
        for (final colorEntry in changes.entries) {
          final color = colorEntry.key;
          final rawColor = stock[color];
          final colorMap = Map<String, dynamic>.from(
              rawColor is Map ? rawColor : <String, dynamic>{});
          for (final sizeEntry in colorEntry.value.entries) {
            final size = sizeEntry.key;
            final q = sizeEntry.value;
            if (q > 0 && !colorMap.containsKey(size)) {
              throw OrderEditException(
                  'المقاس $size ($color) غير موجود في «$name»');
            }
            final current = (colorMap[size] as num?)?.toInt() ?? 0;
            final remaining = current - q;
            if (q > 0 && remaining < 0) {
              // What this order may hold in total: live stock + its own units.
              final held = stored.items
                  .where((i) =>
                      i.productId == productId &&
                      i.color == color &&
                      i.size == size)
                  .fold<int>(0, (n, i) => n + i.quantity);
              final available = current + held;
              throw StockShortageException(
                name: name,
                color: color,
                size: size,
                available: available < 0 ? 0 : available,
              );
            }
            colorMap[size] = remaining;
          }
          stock[color] = colorMap;
        }
        newStock[productId] = stock;
      }

      // ---- what changed ----
      final storedMap = stored.toMap();
      final newMap = order.toMap();
      final fields = [
        for (final k in _editableOrderFields)
          if (_canonical(storedMap[k]) != _canonical(newMap[k])) k,
        if (itemsChanged) 'items',
      ];
      if (fields.isEmpty) {
        saved = stored;
        return;
      }

      final now = DateTime.now();
      final edit = OrderEdit(
        at: now,
        by: 'admin',
        fields: fields,
        itemsBefore: stored.items.length,
        itemsAfter: order.items.length,
        totalBefore: stored.total,
        totalAfter: order.total,
      );
      final history = [...stored.editHistory, edit];
      if (history.length > kMaxOrderEditHistory) {
        history.removeRange(0, history.length - kMaxOrderEditHistory);
      }
      final update = <String, dynamic>{
        for (final k in _editableOrderFields) k: newMap[k],
        if (itemsChanged) ...{
          'items': newMap['items'],
          'subtotal': newMap['subtotal'],
          'cartDiscountAmount': newMap['cartDiscountAmount'],
          'cartDiscountTierMinQuantity': newMap['cartDiscountTierMinQuantity'],
        },
        'updatedAt': now.toIso8601String(),
        'updatedBy': 'admin',
        'editHistory': history.map((e) => e.toMap()).toList(),
      };
      final after = {...live, ...update};

      // ---- writes ----
      for (final entry in newStock.entries) {
        tx.update(_db.collection('products').doc(entry.key), {
          'stock': entry.value,
          'updatedAt': now.toIso8601String(),
        });
      }
      tx.update(orderRef, update);
      _syncCustomersAfterEdit(
        tx,
        before: live,
        after: after,
        stored: stored,
        order: order,
        oldSnap: oldSnap,
        newSnap: newSnap,
        newPhone: newPhone,
      );

      saved = OrderModel.fromMap(after);
    });
    return saved;
  }

  /// Moves an edited order's contribution between customer documents inside
  /// the edit transaction (both were read before any write):
  /// - same phone: `totalOrdersValue` by the total difference, the delivery
  ///   stats by their difference, and name/address refreshed if changed;
  /// - new phone: the old customer loses the order (counters never below 0,
  ///   the document is kept), the new one gains it (created if missing).
  /// Missing customers on the same phone are skipped (orders from before the
  /// customers collection), like [applyCustomerStatsChange].
  void _syncCustomersAfterEdit(
    Transaction tx, {
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
    required OrderModel stored,
    required OrderModel order,
    required DocumentSnapshot<Map<String, dynamic>>? oldSnap,
    required DocumentSnapshot<Map<String, dynamic>>? newSnap,
    required String? newPhone,
  }) {
    final b = OrderCustomerStats.fromOrderData(before);
    final a = OrderCustomerStats.fromOrderData(after);
    final oldTotal = stored.total ?? 0;
    final newTotal = order.total ?? 0;
    final info = {
      'name': order.customerName,
      'city': order.address,
      'area': order.area,
      'street': order.street,
    };
    final now = FieldValue.serverTimestamp();

    // Absolute counter values after the shift, never below 0.
    Map<String, dynamic> shifted(
      Map<String, dynamic> data, {
      int orders = 0,
      double value = 0,
      int delivered = 0,
      double deliveredValue = 0,
      int returned = 0,
    }) {
      int i(String k, int d) {
        final v = ((data[k] as num?)?.toInt() ?? 0) + d;
        return v < 0 ? 0 : v;
      }

      double m(String k, double d) {
        final v = ((data[k] as num?)?.toDouble() ?? 0) + d;
        return v < 0 ? 0 : v;
      }

      return {
        if (orders != 0) 'ordersCount': i('ordersCount', orders),
        if (value.abs() >= 0.0001)
          'totalOrdersValue': m('totalOrdersValue', value),
        if (delivered != 0) 'deliveredCount': i('deliveredCount', delivered),
        if (deliveredValue.abs() >= 0.0001)
          'deliveredValue': m('deliveredValue', deliveredValue),
        if (returned != 0) 'returnedCount': i('returnedCount', returned),
      };
    }

    if (identical(oldSnap, newSnap)) {
      if (oldSnap == null || !oldSnap.exists) return;
      final counters = shifted(
        oldSnap.data()!,
        value: newTotal - oldTotal,
        delivered: a.deliveredCount - b.deliveredCount,
        deliveredValue: a.deliveredValue - b.deliveredValue,
        returned: a.returnedCount - b.returnedCount,
      );
      final infoChanged = stored.customerName != order.customerName ||
          stored.address != order.address ||
          stored.area != order.area ||
          stored.street != order.street;
      if (counters.isEmpty && !infoChanged) return;
      tx.update(oldSnap.reference, {
        ...counters,
        if (infoChanged) ...info,
        'updatedAt': now,
      });
      return;
    }

    if (oldSnap != null && oldSnap.exists) {
      tx.update(oldSnap.reference, {
        ...shifted(
          oldSnap.data()!,
          orders: -1,
          value: -oldTotal,
          delivered: -b.deliveredCount,
          deliveredValue: -b.deliveredValue,
          returned: -b.returnedCount,
        ),
        'updatedAt': now,
      });
    }

    if (newSnap == null || newPhone == null) return;
    final orderAt = Timestamp.fromDate(order.createdAt);
    if (newSnap.exists) {
      final data = newSnap.data()!;
      final first = data['firstOrderAt'];
      final last = data['lastOrderAt'];
      tx.update(newSnap.reference, {
        ...shifted(
          data,
          orders: 1,
          value: newTotal,
          delivered: a.deliveredCount,
          deliveredValue: a.deliveredValue,
          returned: a.returnedCount,
        ),
        ...info,
        if (first is! Timestamp || first.compareTo(orderAt) > 0)
          'firstOrderAt': orderAt,
        if (last is! Timestamp || last.compareTo(orderAt) < 0)
          'lastOrderAt': orderAt,
        'updatedAt': now,
      });
    } else {
      tx.set(newSnap.reference, {
        ...info,
        'phone': newPhone,
        'firstOrderAt': orderAt,
        'lastOrderAt': orderAt,
        'ordersCount': 1,
        'totalOrdersValue': newTotal,
        'deliveredCount': a.deliveredCount,
        'deliveredValue': a.deliveredValue,
        'returnedCount': a.returnedCount,
        'marketingConsent': false,
        'consentUpdatedAt': null,
        'notes': '',
        'tags': <String>[],
        'source': 'manual',
        'createdAt': now,
        'updatedAt': now,
      });
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
            productData[productId] =
                Map<String, dynamic>.from(productSnap.data()!);
          }

          // (4) apply all increments, single tx.update() per product
          for (final productId in restockMap.keys) {
            final productRef = _db.collection('products').doc(productId);
            final data = productData[productId]!;
            final stock = Map<String, dynamic>.from(data['stock'] as Map);

            for (final colorEntry in restockMap[productId]!.entries) {
              final color = colorEntry.key;
              final colorMap = Map<String, dynamic>.from(
                  stock[color] ?? <String, dynamic>{});
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
  // 1) افتح الماسح، ويرجع النص الممسوح أو null عند الإلغاء
  final String? raw = await showDialog<String>(
    context: context,
    builder: (_) => const QrScanDialog(),
  );

  if (raw == null || raw.trim().isEmpty) return;

  final value = raw.trim();
  var code = value.contains('=') ? value.split('=').last.trim() : value;
  if (code.isEmpty) code = value;

  // 2) احفظ الكود
  emit(OrderFormLoadChanged());
  try {
    await _db.collection('orders').doc(order.id).update({
      'qrCode': [code],
    });
    order.qrCode = [code];
  } catch (e) {
    debugPrint('updateOrderQrCode error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ رمز QR، حاول مرة أخرى')),
      );
    }
  } finally {
    if (!isClosed) emit(OrderFormChanged());
  }
}

  /// Orders whose stored `qrCode` holds the scanned [raw] code, in any status
  /// ([currentFilter] is ignored and left unchanged). Checks the loaded
  /// [orders] first, then queries by exact code (`arrayContains`, never the
  /// whole collection), then tries the code as an order id. Never emits;
  /// read errors are thrown to the caller.
  Future<List<OrderModel>> findOrderByBarcode(String raw) async {
    final candidates = barcodeCandidates(raw);
    if (candidates.isEmpty) return const [];

    final loaded =
        orders.where((o) => o.qrCode.any(candidates.contains)).toList();
    if (loaded.isNotEmpty) return loaded;

    final col = _db.collection('orders');
    final snaps = await Future.wait([
      for (final c in candidates)
        col.where('qrCode', arrayContains: c).limit(5).get(),
    ]);
    final found = <String, OrderModel>{};
    for (final snap in snaps) {
      for (final d in snap.docs) {
        found[d.id] = OrderModel.fromMap(d.data());
      }
    }
    if (found.isNotEmpty) return found.values.toList();

    // Codes that encode the order itself (orders have no separate number
    // field, so the document id is the identifier).
    for (final c in candidates) {
      final id = c.startsWith('#') ? c.substring(1) : c;
      if (id.isEmpty || id.contains('/') || id == '.' || id == '..') continue;
      final data = (await col.doc(id).get()).data();
      if (data != null) return [OrderModel.fromMap(data)];
    }
    return const [];
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
