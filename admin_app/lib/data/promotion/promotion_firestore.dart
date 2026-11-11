import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/promotion_pricing.dart';

/// Reads a `promotions/{id}` document. Returns null for a malformed one
/// (missing dates, or neither amountOff nor legacy percent) so a bad doc
/// never breaks the list.
Promotion? promotionFromDoc(String id, Map<String, dynamic> d) {
  final startAt = d['startAt'];
  final endAt = d['endAt'];
  final amountOff = (d['amountOff'] as num?)?.toDouble();
  final percent = (d['percent'] as num?)?.toDouble(); // legacy
  if (startAt is! Timestamp ||
      endAt is! Timestamp ||
      (amountOff == null && percent == null)) {
    return null;
  }
  final ids = d['productIds'];
  final banner = (d['bannerText'] as String?)?.trim();
  return Promotion(
    id: id,
    name: d['name'] as String? ?? '',
    amountOff: amountOff,
    percent: percent,
    productIds: ids is List ? ids.whereType<String>().toList() : const [],
    startAt: startAt.toDate(),
    endAt: endAt.toDate(),
    isActive: d['isActive'] == true,
    bannerText: (banner == null || banner.isEmpty) ? null : banner,
  );
}

/// Editable fields of a promotion, as written to Firestore. `createdAt` /
/// `updatedAt` are added by the cubit. Writes `amountOff`; `percent` only for
/// a legacy promotion with no amount (e.g. duplicating one).
Map<String, dynamic> promotionFields(Promotion p) => {
      'name': p.name.trim(),
      if (p.amountOff != null) 'amountOff': p.amountOff,
      if (p.amountOff == null && p.percent != null) 'percent': p.percent,
      'productIds': p.productIds.take(kMaxPromoProducts).toList(),
      'startAt': Timestamp.fromDate(p.startAt),
      'endAt': Timestamp.fromDate(p.endAt),
      'isActive': p.isActive,
    };
