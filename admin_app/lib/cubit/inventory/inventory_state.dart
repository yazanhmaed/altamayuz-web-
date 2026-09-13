import '../../data/product/product_model.dart';
import 'inventory_cubit.dart' show PendingImportProduct;

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

/// Emitted once an Excel file has been picked and parsed in memory — no
/// Firestore writes have happened yet. Carries the parsed products for the
/// review screen to display and let the admin pick/replace images before
/// [InventoryCubit.confirmImport] actually commits anything. [errors] lists
/// rows/products skipped during parsing (e.g. a new product with no price)
/// — the rest of a valid import still proceeds to review.
class InventoryImportReviewReady extends InventoryState {
  final List<PendingImportProduct> items;
  final List<String> errors;
  InventoryImportReviewReady(this.items, this.errors);
}
