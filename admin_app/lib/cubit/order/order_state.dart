import '../../data/order/order_model.dart';

abstract class OrderState {}

class OrderInitial extends OrderState {}

class OrderLoading extends OrderState {}

class OrderLoaded extends OrderState {
  final List<OrderModel> orders;
  OrderLoaded(this.orders);
}

/// Emitted while a create/edit-order form input changes.
class OrderFormChanged extends OrderState {}

/// Emitted while a longer-running form action is in flight (e.g. QR scan).
class OrderFormLoadChanged extends OrderState {}

class OrderSuccess extends OrderState {
  final String message;
  OrderSuccess(this.message);
}

class OrderError extends OrderState {
  final String message;
  OrderError(this.message);
}
