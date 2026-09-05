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
  final List<ProductVariant> variants;

  const PublicProductModel({
    required this.id,
    required this.name,
    required this.price,
    required this.isFeatured,
    required this.variants,
  });

  bool get isAvailable => variants.any((v) => v.isAvailable);
  String get coverImage =>
      variants.firstWhere((v) => v.isAvailable, orElse: () => variants.first).imageUrl;

  factory PublicProductModel.fromMap(Map<String, dynamic> map) {
    return PublicProductModel(
      id: map['id'] as String,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      isFeatured: map['isFeatured'] as bool? ?? false,
      variants: (map['variants'] as List)
          .map((v) => ProductVariant.fromMap(Map<String, dynamic>.from(v as Map)))
          .toList(),
    );
  }
}
