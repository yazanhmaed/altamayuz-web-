import 'package:cloud_firestore/cloud_firestore.dart';

enum OrderStatus { pending, shipped, completed, returned }

extension OrderStatusX on OrderStatus {
  String get englishName => name;
}

enum ItemStatus { pending, delivered, returned }

extension ItemStatusX on ItemStatus {
  String get englishName => name;
}

/// Orders may store `createdAt` as an ISO string (admin app, storefront) or as
/// a Firestore [Timestamp] (older storefront orders). Accept both.
DateTime _parseDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

class OrderItem {
  final String productId;
  final String? productName;
  final String color;
  final String size;
  final String sku;
  final int quantity;
  final String qrCode;
  final bool isPrimary;
  final String itemId;
  ItemStatus status;

  OrderItem({
    required this.productId,
    required this.color,
    required this.size,
    required this.qrCode,
    required this.sku,
    required this.quantity,
    required this.isPrimary,
    this.productName,
    required this.itemId,
    this.status = ItemStatus.pending,
  });

  OrderItem copyWith({
    String? productId,
    String? productName,
    String? color,
    String? size,
    String? sku,
    String? qrCode,
    int? quantity,
    bool? isPrimary,
    String? itemId,
    ItemStatus? status,
  }) {
    return OrderItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      color: color ?? this.color,
      size: size ?? this.size,
      sku: sku ?? this.sku,
      qrCode: qrCode ?? this.qrCode,
      quantity: quantity ?? this.quantity,
      isPrimary: isPrimary ?? this.isPrimary,
      itemId: itemId ?? this.itemId,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'productId': productId,
    'productName': productName,
    'color': color,
    'size': size,
    'sku': sku,
    'qrCode': qrCode,
    'quantity': quantity,
    'isPrimary': isPrimary,
    'status': status.englishName,
  };

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      itemId: map['itemId'] as String,
      productId: map['productId'] as String,
      productName: map['productName'] as String?,
      color: map['color'] as String,
      size: map['size'] as String,
      sku: map['sku'] as String,
      quantity: (map['quantity'] as num).toInt(),
      isPrimary: (map['isPrimary'] as bool?) ?? true,
      qrCode: map['qrCode'] as String? ?? '',
      status: ItemStatus.values.firstWhere(
        (s) => s.englishName == map['status'],
        orElse: () => ItemStatus.pending,
      ),
    );
  }
}

class OrderModel {
  final String id;
  final String customerName;
  final String customerPhone;
  final String destination;
  final String address; // city
  final String area;    // area/neighbourhood
  final String street;  // optional extra details
  final List<OrderItem> items;
  List<String> qrCode;
  final DateTime createdAt;
  final String deliveryDate;
  final String source; // 'manual' | 'storefront'
  OrderStatus status;

  OrderModel({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.destination,
    required this.address,
    this.area = '',
    required this.street,
    required this.items,
    required this.qrCode,
    required this.createdAt,
    required this.status,
    required this.deliveryDate,
    this.source = 'manual',
  });

  OrderModel copyWith({
    String? id,
    String? customerName,
    String? customerPhone,
    String? destination,
    String? address,
    String? area,
    String? street,
    List<OrderItem>? items,
    List<String>? qrCode,
    DateTime? createdAt,
    String? deliveryDate,
    OrderStatus? status,
    String? source,
  }) {
    return OrderModel(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      destination: destination ?? this.destination,
      address: address ?? this.address,
      area: area ?? this.area,
      street: street ?? this.street,
      items: items ?? this.items,
      qrCode: qrCode ?? this.qrCode,
      createdAt: createdAt ?? this.createdAt,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      status: status ?? this.status,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'destination': destination,
    'address': address,
    'area': area,
    'street': street,
    'items': items.map((e) => e.toMap()).toList(),
    'qrCode': qrCode,
    'createdAt': createdAt.toIso8601String(),
    'deliveryDate': deliveryDate,
    'status': status.englishName,
    'source': source,
  };

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'] as String,
      customerName: map['customerName'] as String,
      customerPhone: map['customerPhone'] as String,
      destination: map['destination'] as String? ?? '',
      address: map['address'] as String? ?? '',
      area: map['area'] as String? ?? '',
      street: map['street'] as String? ?? '',
      items: (map['items'] as List)
          .map((e) => OrderItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      qrCode: List<String>.from(map['qrCode'] ?? []),
      createdAt: _parseDate(map['createdAt']),
      deliveryDate: map['deliveryDate'] as String? ?? '',
      status: OrderStatus.values.firstWhere(
        (s) => s.englishName == map['status'],
        orElse: () => OrderStatus.pending,
      ),
      source: map['source'] as String? ?? 'manual',
    );
  }
}
