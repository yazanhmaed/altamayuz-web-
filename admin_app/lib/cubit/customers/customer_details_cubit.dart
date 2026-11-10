import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/customer/customer_model.dart';
import '../../data/order/order_model.dart';

const int kCustomerOrdersPageSize = 10;

class CustomerDetailsState {
  final CustomerModel? customer;
  final bool loading;
  final String? error;
  final List<OrderModel> orders;
  final bool ordersLoading;
  final bool ordersLoadingMore;
  final bool hasMoreOrders;
  final String? ordersError;
  final bool saving;

  /// One-shot message for a snackbar (save confirmations / failures).
  final String? message;

  const CustomerDetailsState({
    this.customer,
    this.loading = true,
    this.error,
    this.orders = const [],
    this.ordersLoading = true,
    this.ordersLoadingMore = false,
    this.hasMoreOrders = true,
    this.ordersError,
    this.saving = false,
    this.message,
  });

  CustomerDetailsState copyWith({
    CustomerModel? customer,
    bool? loading,
    String? error,
    bool clearError = false,
    List<OrderModel>? orders,
    bool? ordersLoading,
    bool? ordersLoadingMore,
    bool? hasMoreOrders,
    String? ordersError,
    bool clearOrdersError = false,
    bool? saving,
    String? message,
  }) {
    return CustomerDetailsState(
      customer: customer ?? this.customer,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      orders: orders ?? this.orders,
      ordersLoading: ordersLoading ?? this.ordersLoading,
      ordersLoadingMore: ordersLoadingMore ?? this.ordersLoadingMore,
      hasMoreOrders: hasMoreOrders ?? this.hasMoreOrders,
      ordersError: clearOrdersError ? null : (ordersError ?? this.ordersError),
      saving: saving ?? this.saving,
      message: message, // never carried over
    );
  }
}

/// One customer's profile: the customer doc, owner edits (consent, notes,
/// tags), and their orders 10 at a time.
class CustomerDetailsCubit extends Cubit<CustomerDetailsState> {
  CustomerDetailsCubit(this.customerId, {CustomerModel? initial})
      : super(CustomerDetailsState(customer: initial, loading: initial == null));

  final String customerId;
  final _db = FirebaseFirestore.instance;
  DocumentSnapshot<Map<String, dynamic>>? _lastOrderDoc;
  int _ordersGen = 0;

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection('customers').doc(customerId);

  Future<void> load() async {
    await Future.wait([reloadCustomer(), reloadOrders()]);
  }

  Future<void> reloadCustomer() async {
    try {
      final doc = await _ref.get();
      if (isClosed) return;
      if (!doc.exists) {
        emit(state.copyWith(loading: false, error: 'العميل غير موجود.'));
        return;
      }
      emit(state.copyWith(
        customer: CustomerModel.fromDoc(doc),
        loading: false,
        clearError: true,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Query<Map<String, dynamic>> get _ordersQuery => _db
      .collection('orders')
      .where('customerPhone', isEqualTo: customerId)
      .orderBy('createdAt', descending: true)
      .limit(kCustomerOrdersPageSize);

  Future<void> reloadOrders() async {
    final gen = ++_ordersGen;
    _lastOrderDoc = null;
    emit(state.copyWith(
      orders: const [],
      ordersLoading: true,
      hasMoreOrders: true,
      clearOrdersError: true,
    ));
    await _fetchOrders(gen);
  }

  Future<void> loadMoreOrders() async {
    if (state.ordersLoading || state.ordersLoadingMore || !state.hasMoreOrders) {
      return;
    }
    emit(state.copyWith(ordersLoadingMore: true, clearOrdersError: true));
    await _fetchOrders(_ordersGen);
  }

  Future<void> _fetchOrders(int gen) async {
    try {
      var q = _ordersQuery;
      if (_lastOrderDoc != null) q = q.startAfterDocument(_lastOrderDoc!);
      final snap = await q.get();
      if (gen != _ordersGen || isClosed) return;
      if (snap.docs.isNotEmpty) _lastOrderDoc = snap.docs.last;
      emit(state.copyWith(
        orders: [...state.orders, ...snap.docs.map((d) => OrderModel.fromMap(d.data()))],
        ordersLoading: false,
        ordersLoadingMore: false,
        hasMoreOrders: snap.docs.length == kCustomerOrdersPageSize,
      ));
    } catch (e) {
      if (gen != _ordersGen || isClosed) return;
      emit(state.copyWith(
        ordersLoading: false,
        ordersLoadingMore: false,
        ordersError: e.toString(),
      ));
    }
  }

  Future<void> _save(Map<String, dynamic> data, String okMessage) async {
    emit(state.copyWith(saving: true));
    try {
      await _ref.update({...data, 'updatedAt': FieldValue.serverTimestamp()});
      final doc = await _ref.get();
      if (isClosed) return;
      emit(state.copyWith(
        customer: CustomerModel.fromDoc(doc),
        saving: false,
        message: okMessage,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(saving: false, message: 'تعذر الحفظ: $e'));
    }
  }

  /// Owner-side consent change (e.g. the customer asked to stop offers).
  Future<void> setConsent(bool value) => _save({
        'marketingConsent': value,
        'consentUpdatedAt': FieldValue.serverTimestamp(),
      }, value ? 'تم تفعيل الموافقة على العروض.' : 'تم إلغاء الموافقة على العروض.');

  /// Customer replied "إيقاف": stop offers. Campaigns only ever load
  /// consenting customers, so they disappear from every send list.
  Future<void> optOut() => _save({
        'marketingConsent': false,
        'consentUpdatedAt': FieldValue.serverTimestamp(),
      }, 'تم تسجيل طلب الإيقاف.');

  Future<void> saveNotes(String notes) =>
      _save({'notes': notes.trim()}, 'تم حفظ الملاحظات.');

  Future<void> addTag(String tag) async {
    final t = tag.trim();
    if (t.isEmpty || (state.customer?.tags.contains(t) ?? false)) return;
    await _save({'tags': FieldValue.arrayUnion([t])}, 'تمت إضافة الوسم.');
  }

  Future<void> removeTag(String tag) =>
      _save({'tags': FieldValue.arrayRemove([tag])}, 'تمت إزالة الوسم.');
}
