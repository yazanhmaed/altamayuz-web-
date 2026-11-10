import 'package:cloud_firestore/cloud_firestore.dart';

/// VIP threshold for the "VIP" segment: customers whose delivered purchases
/// reach this many JOD.
const double kVipDeliveredValueThreshold = 300;

/// A customer is "خامل" (inactive) when their last order is older than this.
const int kInactiveAfterDays = 60;

/// "مرتجعات عالية" starts at this many returned items.
const int kHighReturnsThreshold = 2;

/// Suggested tags offered on the customer profile.
const List<String> kSuggestedCustomerTags = ['VIP', 'جملة', 'مشكلة بالتسليم'];

DateTime? _date(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// One `customers/{E.164 phone}` document. Written by submitPublicOrder and
/// the admin order flow; the derived delivery stats are kept in sync by the
/// order status transactions in OrderCubit.
class CustomerModel {
  final String id; // E.164 phone, same as [phone]
  final String name;
  final String phone;
  final String city;
  final String area;
  final String street;
  final DateTime? firstOrderAt;
  final DateTime? lastOrderAt;
  final int ordersCount;
  final double totalOrdersValue;
  final int deliveredCount;
  final double deliveredValue;
  final int returnedCount;
  final bool marketingConsent;
  final DateTime? consentUpdatedAt;
  final String notes;
  final List<String> tags;
  final String source;

  /// Last time an offer was opened in WhatsApp for this customer.
  final DateTime? lastContactedAt;

  const CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    this.city = '',
    this.area = '',
    this.street = '',
    this.firstOrderAt,
    this.lastOrderAt,
    this.ordersCount = 0,
    this.totalOrdersValue = 0,
    this.deliveredCount = 0,
    this.deliveredValue = 0,
    this.returnedCount = 0,
    this.marketingConsent = false,
    this.consentUpdatedAt,
    this.notes = '',
    this.tags = const [],
    this.source = '',
    this.lastContactedAt,
  });

  factory CustomerModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return CustomerModel(
      id: doc.id,
      name: m['name'] as String? ?? '',
      phone: m['phone'] as String? ?? doc.id,
      city: m['city'] as String? ?? '',
      area: m['area'] as String? ?? '',
      street: m['street'] as String? ?? '',
      firstOrderAt: _date(m['firstOrderAt']),
      lastOrderAt: _date(m['lastOrderAt']),
      ordersCount: (m['ordersCount'] as num?)?.toInt() ?? 0,
      totalOrdersValue: (m['totalOrdersValue'] as num?)?.toDouble() ?? 0,
      deliveredCount: (m['deliveredCount'] as num?)?.toInt() ?? 0,
      deliveredValue: (m['deliveredValue'] as num?)?.toDouble() ?? 0,
      returnedCount: (m['returnedCount'] as num?)?.toInt() ?? 0,
      marketingConsent: m['marketingConsent'] as bool? ?? false,
      consentUpdatedAt: _date(m['consentUpdatedAt']),
      notes: m['notes'] as String? ?? '',
      tags: List<String>.from(m['tags'] as List? ?? const []),
      source: m['source'] as String? ?? '',
      lastContactedAt: _date(m['lastContactedAt']),
    );
  }

  bool get isNew => ordersCount == 1;
  bool get isRepeat => ordersCount >= 2;
  bool get isVip => deliveredValue >= kVipDeliveredValueThreshold;
  bool get isHighReturns => returnedCount >= kHighReturnsThreshold;
  bool get isInactive =>
      lastOrderAt != null &&
      lastOrderAt!.isBefore(
          DateTime.now().subtract(const Duration(days: kInactiveAfterDays)));

  /// Average delivered order value, or null before any delivery.
  double? get averageOrderValue =>
      deliveredCount > 0 ? deliveredValue / deliveredCount : null;

  /// Digits only (no `+`), as wa.me expects.
  String get whatsappDigits => phone.replaceAll(RegExp(r'\D'), '');
}
