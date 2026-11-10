import '../../data/customer/customer_model.dart';

enum CustomerSort { recent, mostOrders, topSpend }

enum CustomerSegment { all, newCustomer, repeat, vip, inactive, consent, highReturns }

class CustomersState {
  /// Pages loaded so far for the current sort/segment/phone search.
  final List<CustomerModel> customers;
  final bool loading; // first page
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final CustomerSort sort;
  final CustomerSegment segment;
  final String search;

  const CustomersState({
    this.customers = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
    this.sort = CustomerSort.recent,
    this.segment = CustomerSegment.all,
    this.search = '',
  });

  CustomersState copyWith({
    List<CustomerModel>? customers,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    CustomerSort? sort,
    CustomerSegment? segment,
    String? search,
  }) {
    return CustomersState(
      customers: customers ?? this.customers,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      sort: sort ?? this.sort,
      segment: segment ?? this.segment,
      search: search ?? this.search,
    );
  }
}
