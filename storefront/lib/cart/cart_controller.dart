import 'package:flutter/foundation.dart';
import '../models/public_product_model.dart';

class CartLine {
  final PublicProductModel product;
  final ProductVariant variant;
  final String size;
  int quantity;

  CartLine({required this.product, required this.variant, required this.size, this.quantity = 1});

  double get lineTotal => product.price * quantity;
  String get key => '${product.id}-${variant.color}-$size';
}

class CartController extends ValueNotifier<List<CartLine>> {
  CartController() : super([]);

  double get total => value.fold(0, (sum, l) => sum + l.lineTotal);
  int get itemCount => value.fold(0, (sum, l) => sum + l.quantity);

  void add(PublicProductModel product, ProductVariant variant, String size) {
    final i = value.indexWhere(
      (l) => l.product.id == product.id && l.variant.color == variant.color && l.size == size,
    );
    if (i >= 0) {
      value[i].quantity++;
    } else {
      value.add(CartLine(product: product, variant: variant, size: size));
    }
    notifyListeners();
  }

  void remove(String key) {
    value.removeWhere((l) => l.key == key);
    notifyListeners();
  }

  void updateQuantity(String key, int qty) {
    final line = value.firstWhere((l) => l.key == key);
    if (qty <= 0) {
      remove(key);
    } else {
      line.quantity = qty;
      notifyListeners();
    }
  }

  void clear() {
    value.clear();
    notifyListeners();
  }
}

final cartController = CartController();
