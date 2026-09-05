import '../../data/product/product_model.dart';

abstract class InventoryState {}

class InventoryInitial extends InventoryState {}

class InventoryLoading extends InventoryState {}

class InventoryLoaded extends InventoryState {
  final List<ProductModel> products;
  InventoryLoaded(this.products);
}

/// Emitted whenever the add/edit-product form fields change, so the form
/// widget rebuilds without touching the product list.
class InventoryFormChanged extends InventoryState {}

/// Emitted when a dynamic row (color row or restock row) is added/removed.
class InventoryAddRow extends InventoryState {}

class InventorySuccess extends InventoryState {
  final String message;
  InventorySuccess(this.message);
}

class InventoryError extends InventoryState {
  final String message;
  InventoryError(this.message);
}
