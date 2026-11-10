import 'package:cloud_firestore/cloud_firestore.dart';

import '../customer/customer_model.dart';

/// Always appended to every offer message.
const String kOptOutLine = 'للإيقاف أرسل: إيقاف';

const String kDefaultOfferLink = 'https://www.altamayuzshop.com';

/// Soft daily limit: past this many contacted customers today the screen
/// shows a ban-risk warning (sending is still allowed).
const int kDailySoftSendLimit = 50;

/// Minimum gap between two sends.
const Duration kSendCooldown = Duration(seconds: 3);

/// Who a campaign targets. Every audience is limited to customers with
/// `marketingConsent == true`; the segments use the same definitions as the
/// customers screen (CustomerModel getters).
enum OfferAudience { allConsenting, repeat, vip, inactive, newCustomer }

const offerAudienceLabels = {
  OfferAudience.allConsenting: 'الكل الموافقين',
  OfferAudience.repeat: 'متكرر',
  OfferAudience.vip: 'VIP',
  OfferAudience.inactive: 'خامل',
  OfferAudience.newCustomer: 'جديد',
};

bool audienceIncludes(OfferAudience a, CustomerModel c) {
  if (!c.marketingConsent) return false;
  return switch (a) {
    OfferAudience.allConsenting => true,
    OfferAudience.repeat => c.isRepeat,
    OfferAudience.vip => c.isVip,
    OfferAudience.inactive => c.isInactive,
    OfferAudience.newCustomer => c.isNew,
  };
}

class OfferTemplatePreset {
  final String label;
  final String text;
  const OfferTemplatePreset(this.label, this.text);
}

const offerTemplatePresets = [
  OfferTemplatePreset(
    'عرض جديد',
    'أهلاً {name} 👋 عندنا عرض جديد في التميز للجلود الطبيعية: {offer}. تصفح: {link}',
  ),
  OfferTemplatePreset(
    'نشتاقلك',
    'أهلاً {name}، اشتقنالك! جهزنالك موديلات جديدة: {link}',
  ),
  OfferTemplatePreset(
    'وصلت موديلات جديدة',
    'أهلاً {name} 👋 وصلت موديلات جديدة في التميز للجلود الطبيعية! تصفحها الآن: {link}',
  ),
  OfferTemplatePreset('نص حر', ''),
];

/// First word of the customer's name, or a neutral greeting word if blank.
String offerFirstName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.first.isEmpty ? 'عميلنا العزيز' : parts.first;
}

/// Fills {name}/{offer}/{link} and always ends with the opt-out line.
String buildOfferMessage({
  required String template,
  required String customerName,
  required String offer,
  required String link,
}) {
  final l = link.trim().isEmpty ? kDefaultOfferLink : link.trim();
  var msg = template
      .replaceAll('{name}', offerFirstName(customerName))
      .replaceAll('{offer}', offer.trim())
      .replaceAll('{link}', l)
      .trim();
  if (!msg.contains(kOptOutLine)) msg = '$msg\n\n$kOptOutLine';
  return msg;
}

/// wa.me link with the message percent-encoded as UTF-8 (Arabic and emoji
/// safe; spaces become %20, not `+`).
Uri whatsappMessageUri(String phone, String message) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
}

/// `campaigns/{id}` header, as listed in the campaign picker.
class CampaignSummary {
  final String id;
  final String title;
  final OfferAudience audience;
  final String template;
  final String offer;
  final String link;
  final DateTime? createdAt;
  final int sentCount;

  const CampaignSummary({
    required this.id,
    required this.title,
    required this.audience,
    required this.template,
    this.offer = '',
    this.link = kDefaultOfferLink,
    this.createdAt,
    this.sentCount = 0,
  });

  factory CampaignSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return CampaignSummary(
      id: doc.id,
      title: m['title'] as String? ?? '',
      audience: OfferAudience.values.firstWhere(
        (a) => a.name == m['audience'],
        orElse: () => OfferAudience.allConsenting,
      ),
      template: m['template'] as String? ?? '',
      offer: m['offer'] as String? ?? '',
      link: m['link'] as String? ?? kDefaultOfferLink,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      sentCount: (m['sentCount'] as num?)?.toInt() ?? 0,
    );
  }
}
