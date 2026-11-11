import 'package:flutter/foundation.dart';
import '../data/promotions_repository.dart';
import '../models/public_product_model.dart';

class CartLine {
  final PublicProductModel product;
  final ProductVariant variant;
  final String size;
  int quantity;

  CartLine({required this.product, required this.variant, required this.size, this.quantity = 1});

  double get lineTotal => product.effectivePrice * quantity;
  String get key => '${product.id}-${variant.color}-$size';
}

class CartController extends ValueNotifier<List<CartLine>> {
  CartController() : super([]) {
    promotionsRepository.addListener(_onPromotionsChanged);
  }

  /// Unit price each line was last shown at, by [CartLine.key].
  final Map<String, double> _shownPrices = {};

  /// True after a promotion change moved the price of something in the cart.
  /// Shown as a gentle "تم تحديث الأسعار" note until dismissed.
  final ValueNotifier<bool> pricesUpdated = ValueNotifier(false);

  void _onPromotionsChanged() {
    var changed = false;
    for (final l in value) {
      final now = l.product.effectivePrice;
      if (_shownPrices[l.key] != now) {
        changed = true;
        _shownPrices[l.key] = now;
      }
    }
    if (changed) {
      pricesUpdated.value = true;
      notifyListeners();
    }
  }

  void dismissPricesUpdated() => pricesUpdated.value = false;

  double get total => value.fold(0, (sum, l) => sum + l.lineTotal);
  int get itemCount => value.fold(0, (sum, l) => sum + l.quantity);

  void add(PublicProductModel product, ProductVariant variant, String size) {
    final i = value.indexWhere(
      (l) => l.product.id == product.id && l.variant.color == variant.color && l.size == size,
    );
    if (i >= 0) {
      value[i].quantity++;
    } else {
      final line = CartLine(product: product, variant: variant, size: size);
      value.add(line);
      _shownPrices[line.key] = product.effectivePrice;
    }
    notifyListeners();
  }

  void remove(String key) {
    value.removeWhere((l) => l.key == key);
    _shownPrices.remove(key);
    if (value.isEmpty) pricesUpdated.value = false;
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
    _shownPrices.clear();
    pricesUpdated.value = false;
    notifyListeners();
  }
}

final cartController = CartController();
