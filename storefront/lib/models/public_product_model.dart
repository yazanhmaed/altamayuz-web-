class ProductVariant {
  final String color;
  final String imageUrl;
  final Map<String, int> sizes;

  const ProductVariant({required this.color, required this.imageUrl, required this.sizes});

  bool get isAvailable => sizes.values.any((q) => q > 0);
  List<String> get availableSizes =>
      sizes.entries.where((e) => e.value > 0).map((e) => e.key).toList();

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      color: map['color'] as String,
      imageUrl: map['imageUrl'] as String? ?? '',
      sizes: Map<String, int>.from(
        (map['sizes'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
      ),
    );
  }
}

class PublicProductModel {
  final String id;
  final String name;
  final double price;
  final bool isFeatured;
  final String category;
  final List<ProductVariant> variants;

  const PublicProductModel({
    required this.id,
    required this.name,
    required this.price,
    required this.isFeatured,
    required this.category,
    required this.variants,
  });

  bool get isAvailable => variants.any((v) => v.isAvailable);
  String get coverImage {
    if (variants.isEmpty) return '';
    return variants
        .firstWhere((v) => v.isAvailable, orElse: () => variants.first)
        .imageUrl;
  }

  factory PublicProductModel.fromMap(Map<String, dynamic> map) {
    return PublicProductModel(
      id: map['id'] as String,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      isFeatured: map['isFeatured'] as bool? ?? false,
      category: map['category'] as String? ?? 'عام',
      variants: (map['variants'] as List)
          .map((v) => ProductVariant.fromMap(Map<String, dynamic>.from(v as Map)))
          .toList(),
    );
  }

  /// Builds the storefront model straight from an admin `products/{id}` doc,
  /// applying the same shaping the `syncPublicProduct` Cloud Function would
  /// (colors + stock + imageUrls → variants). Returns null for docs that are
  /// not sellable (inactive, no price, or no colors).
  static PublicProductModel? fromProductDoc(String id, Map<String, dynamic> map) {
    final isActive = map['isActive'] as bool? ?? false;
    final price = (map['price'] as num?)?.toDouble() ?? 0;
    if (!isActive || price <= 0) return null;

    final colors = (map['colors'] as List?)?.cast<String>() ?? const <String>[];
    if (colors.isEmpty) return null;

    final stock = (map['stock'] as Map?) ?? const {};
    final imageUrls = (map['imageUrls'] as Map?) ?? const {};

    final variants = colors.map((color) {
      final rawSizes = (stock[color] as Map?) ?? const {};
      final sizes = <String, int>{
        for (final e in rawSizes.entries)
          e.key as String: (e.value as num).toInt(),
      };
      return ProductVariant(
        color: color,
        imageUrl: imageUrls[color] as String? ?? '',
        sizes: sizes,
      );
    }).toList();

    return PublicProductModel(
      id: id,
      name: map['name'] as String? ?? '',
      price: price,
      isFeatured: map['isFeatured'] as bool? ?? false,
      category: map['category'] as String? ?? 'عام',
      variants: variants,
    );
  }
}
