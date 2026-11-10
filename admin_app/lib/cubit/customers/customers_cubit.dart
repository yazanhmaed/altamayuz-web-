import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/customer/customer_model.dart';
import '../../data/customer/customer_stats.dart';
import '../../utils/arabic_search.dart';
import '../../utils/jordan_phone.dart';
import 'customers_state.dart';

const int kCustomersPageSize = 20;

/// Turns phone-looking search text into a doc-ID prefix: `079 12` →
/// `+96279 12` (digits only), `+96279…`/`0096279…` → `+96279…`, Arabic
/// digits allowed. Returns null when the text isn't a phone (e.g. a name).
String? phoneSearchPrefix(String query) {
  final t = toAsciiDigits(query).trim();
  if (t.isEmpty || !RegExp(r'^[\d\s+\-()]+$').hasMatch(t)) return null;
  if (!RegExp(r'\d').hasMatch(t)) return null;
  var digits = t.replaceAll(RegExp(r'\D'), '');
  digits = digits.replaceFirst(RegExp(r'^00'), '');
  if (digits.startsWith('962')) digits = digits.substring(3);
  digits = digits.replaceFirst(RegExp(r'^0+'), '');
  return '$jordanDialCode$digits';
}

/// Paginated customers list (20 per page via startAfterDocument). Never
/// streams or loads the whole collection. Sort and segment run as Firestore
/// queries; name search filters the pages already loaded.
class CustomersCubit extends Cubit<CustomersState> {
  CustomersCubit() : super(const CustomersState());

  final _db = FirebaseFirestore.instance;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  Timestamp _inactiveCutoff = Timestamp.now();
  bool _started = false;
  int _generation = 0; // drops results of a query that was replaced
  Timer? _searchDebounce;

  /// Customers to show: loaded pages, narrowed by name when the search isn't
  /// a phone number.
  List<CustomerModel> get visibleCustomers {
    final q = state.search.trim();
    if (q.isEmpty || phoneSearchPrefix(q) != null) return state.customers;
    return state.customers
        .where((c) => matchesSearch(q, [c.name]))
        .toList();
  }

  bool get isNameSearch =>
      state.search.trim().isNotEmpty && phoneSearchPrefix(state.search) == null;

  bool get isPhoneSearch => phoneSearchPrefix(state.search) != null;

  void start() {
    if (_started) return;
    _started = true;
    refresh();
  }

  Future<void> refresh() => _reset();

  void setSort(CustomerSort sort) {
    if (sort == state.sort) return;
    emit(state.copyWith(sort: sort));
    _reset();
  }

  void setSegment(CustomerSegment segment) {
    if (segment == state.segment) return;
    emit(state.copyWith(segment: segment));
    _reset();
  }

  void setSearch(String text) {
    final oldPrefix = phoneSearchPrefix(state.search);
    final newPrefix = phoneSearchPrefix(text);
    emit(state.copyWith(search: text));
    // Name search is client-side; only a phone prefix change needs a query.
    if (oldPrefix != newPrefix) {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 350), _reset);
    }
  }

  String _sortField(CustomerSort sort) => switch (sort) {
        CustomerSort.recent => 'lastOrderAt',
        CustomerSort.mostOrders => 'ordersCount',
        CustomerSort.topSpend => 'totalOrdersValue',
      };

  /// Every combination here has a matching composite index in
  /// firestore.indexes.json. A range segment adds its own field as a second
  /// orderBy so pagination cursors include it.
  Query<Map<String, dynamic>> _query() {
    final col = _db.collection('customers');

    final prefix = phoneSearchPrefix(state.search);
    if (prefix != null) {
      return col
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
          .where(FieldPath.documentId, isLessThan: '$prefix')
          .orderBy(FieldPath.documentId);
    }

    var sortField = _sortField(state.sort);
    Query<Map<String, dynamic>> q = col;
    String? rangeField;
    switch (state.segment) {
      case CustomerSegment.all:
        break;
      case CustomerSegment.newCustomer:
        q = q.where('ordersCount', isEqualTo: 1);
        // Everyone here has 1 order; "most orders" falls back to recent.
        if (sortField == 'ordersCount') sortField = 'lastOrderAt';
      case CustomerSegment.repeat:
        q = q.where('ordersCount', isGreaterThanOrEqualTo: 2);
        rangeField = 'ordersCount';
      case CustomerSegment.vip:
        q = q.where('deliveredValue',
            isGreaterThanOrEqualTo: kVipDeliveredValueThreshold);
        rangeField = 'deliveredValue';
      case CustomerSegment.inactive:
        q = q.where('lastOrderAt', isLessThan: _inactiveCutoff);
        rangeField = 'lastOrderAt';
      case CustomerSegment.consent:
        q = q.where('marketingConsent', isEqualTo: true);
      case CustomerSegment.highReturns:
        q = q.where('returnedCount',
            isGreaterThanOrEqualTo: kHighReturnsThreshold);
        rangeField = 'returnedCount';
    }
    q = q.orderBy(sortField, descending: true);
    if (rangeField != null && rangeField != sortField) {
      q = q.orderBy(rangeField, descending: true);
    }
    return q;
  }

  Future<void> _reset() async {
    _searchDebounce?.cancel();
    final gen = ++_generation;
    _lastDoc = null;
    _inactiveCutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: kInactiveAfterDays)),
    );
    emit(state.copyWith(
      customers: const [],
      loading: true,
      loadingMore: false,
      hasMore: true,
      clearError: true,
    ));
    await _fetchPage(gen);
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    emit(state.copyWith(loadingMore: true, clearError: true));
    await _fetchPage(_generation);
  }

  Future<void> _fetchPage(int gen) async {
    try {
      var q = _query().limit(kCustomersPageSize);
      if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
      final snap = await q.get();
      if (gen != _generation || isClosed) return;
      if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
      emit(state.copyWith(
        customers: [
          ...state.customers,
          ...snap.docs.map(CustomerModel.fromDoc),
        ],
        loading: false,
        loadingMore: false,
        hasMore: snap.docs.length == kCustomersPageSize,
      ));
    } catch (e) {
      if (gen != _generation || isClosed) return;
      emit(state.copyWith(loading: false, loadingMore: false, error: e.toString()));
    }
  }

  /// Replaces one customer in the loaded list (after a profile edit) without
  /// refetching.
  void replaceCustomer(CustomerModel customer) {
    final i = state.customers.indexWhere((c) => c.id == customer.id);
    if (i == -1) return;
    final list = [...state.customers]..[i] = customer;
    emit(state.copyWith(customers: list));
  }

  /// Re-reads one customer (e.g. after returning from their profile) and
  /// updates it in place.
  Future<void> refreshOne(String id) async {
    try {
      final doc = await _db.collection('customers').doc(id).get();
      if (doc.exists && !isClosed) replaceCustomer(CustomerModel.fromDoc(doc));
    } catch (_) {
      // Stale row is harmless; pull-to-refresh fixes it.
    }
  }

  /// Hidden repair action: rebuilds one customer's counters from their
  /// orders. Returns a message for the UI.
  Future<String> recomputeStats(String rawPhone) async {
    final phone = normalizePhoneE164(rawPhone);
    if (phone == null) return 'رقم الهاتف غير صحيح.';
    try {
      final n = await recomputeCustomerStats(_db, phone);
      final doc = await _db.collection('customers').doc(phone).get();
      if (doc.exists) replaceCustomer(CustomerModel.fromDoc(doc));
      return 'تمت إعادة حساب الإحصائيات ($n طلب).';
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    return super.close();
  }
}
