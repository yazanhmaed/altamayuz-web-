class ProductModel {
  final String id;
  final String name;
  final double price;
  final List<String> colors;
  final Map<String, String> imageUrls; // color -> image URL
  final Map<String, Map<String, int>> stock; // color -> size -> qty
  final bool isActive;
  final bool isFeatured; // shown on storefront homepage hero/carousel
  final int lowStockThreshold;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductModel({
    required this.id,
    required this.name,
    required this.price,
    required this.colors,
    required this.imageUrls,
    required this.stock,
    required this.isActive,
    this.isFeatured = false,
    required this.lowStockThreshold,
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalQty => stock.values
      .expand((sizeMap) => sizeMap.values)
      .fold(0, (sum, q) => sum + q);

  String? imageFor(String color) =>
      imageUrls[color]?.isNotEmpty == true ? imageUrls[color] : null;

  ProductModel copyWith({
    String? id,
    String? name,
    double? price,
    List<String>? colors,
    Map<String, String>? imageUrls,
    Map<String, Map<String, int>>? stock,
    bool? isActive,
    bool? isFeatured,
    int? lowStockThreshold,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      colors: colors ?? this.colors,
      imageUrls: imageUrls ?? this.imageUrls,
      stock: stock ?? this.stock,
      isActive: isActive ?? this.isActive,
      isFeatured: isFeatured ?? this.isFeatured,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'price': price,
    'colors': colors,
    'imageUrls': imageUrls,
    'stock': stock,
    'isActive': isActive,
    'isFeatured': isFeatured,
    'lowStockThreshold': lowStockThreshold,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as String,
      name: map['name'] as String,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      colors: List<String>.from(map['colors'] ?? []),
      imageUrls: Map<String, String>.from(map['imageUrls'] ?? {}),
      stock: (map['stock'] as Map? ?? {}).map(
        (color, sizes) => MapEntry(
          color as String,
          Map<String, int>.from(
            (sizes as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
          ),
        ),
      ),
      isActive: map['isActive'] as bool? ?? true,
      isFeatured: map['isFeatured'] as bool? ?? false,
      lowStockThreshold: (map['lowStockThreshold'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  String toString() => 'Product($id, $name, totalQty: $totalQty)';
}
