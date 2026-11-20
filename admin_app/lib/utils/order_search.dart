import '../data/order/order_model.dart';
import 'arabic_search.dart';
import 'jordan_phone.dart';

/// In-memory orders search (no Firestore queries): true when EVERY word of
/// [query] appears in one of the order's fields — customer name, phone,
/// governorate, area, street, destination, order id (any part, so the short
/// `#ABC123` shown on cards works), notes, and each item's product name,
/// color, size and promotion name. Text is folded with [normalizeForSearch]
/// (case, Arabic digits, tashkeel, أ/إ/آ, ة, ى).
///
/// A phone-looking word also matches the order's local number by digits, so
/// `0791234567`, `791234567`, `+962791234567`, `00962…` and the last digits
/// (`4567`) all find the same order; dashes and parentheses are ignored.
bool orderMatchesSearch(OrderModel order, String query) {
  final words = normalizeForSearch(query)
      .split(RegExp(r'\s+'))
      .map((w) => w.startsWith('#') ? w.substring(1) : w)
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;

  final fields = [
    order.customerName,
    order.customerPhone,
    order.address,
    order.area,
    order.street,
    order.destination,
    order.id,
    order.discountNote,
    for (final item in order.items) ...[
      item.productName ?? '',
      item.color,
      item.size,
      item.promoName ?? '',
    ],
  ].map(normalizeForSearch).toList();
  final localPhone = jordanPhoneToLocal(order.customerPhone);

  return words.every(
      (w) => fields.any((f) => f.contains(w)) || _phoneMatches(w, localPhone));
}

bool _phoneMatches(String word, String localPhone) {
  if (localPhone.isEmpty || !RegExp(r'^[\d+\-()]+$').hasMatch(word)) {
    return false;
  }
  var digits = word.replaceAll(RegExp(r'\D'), '');
  digits = digits.replaceFirst(RegExp(r'^00'), '');
  if (digits.startsWith('962') && digits.length > 3) digits = digits.substring(3);
  digits = digits.replaceFirst(RegExp(r'^0+'), '');
  return digits.isNotEmpty && localPhone.contains(digits);
}

/// A scanned or typed code with control, zero-width and bidi characters
/// removed (scanners and copy/paste can add them), trimmed.
String normalizeBarcode(String raw) => raw
    .replaceAll(
        RegExp(
            r'[\x00-\x1F\x7F-\x9F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'),
        '')
    .trim();

/// Values an order's stored `qrCode` may hold for [raw]: the whole code and,
/// for URL-style codes, the part after the last `=` (what `updateOrderQrCode`
/// saves).
List<String> barcodeCandidates(String raw) {
  final value = normalizeBarcode(raw);
  if (value.isEmpty) return const [];
  final tail = value.contains('=') ? value.split('=').last.trim() : '';
  return [value, if (tail.isNotEmpty && tail != value) tail];
}

/// True when a submitted search looks like a scanned code rather than a name
/// or phone: one word, at least 6 characters, and not a Jordanian mobile
/// number (`0791234567`, `+962791234567`, …).
bool looksLikeBarcode(String text) {
  final value = normalizeBarcode(text);
  if (value.length < 6 || value.contains(RegExp(r'\s'))) return false;
  final ascii = toAsciiDigits(value);
  if (RegExp(r'^[\d+\-()]+$').hasMatch(ascii)) {
    var digits = ascii.replaceAll(RegExp(r'\D'), '');
    digits = digits.replaceFirst(RegExp(r'^00'), '');
    if (digits.startsWith('962')) digits = digits.substring(3);
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (RegExp(r'^7\d{8}$').hasMatch(digits)) return false;
  }
  return true;
}
