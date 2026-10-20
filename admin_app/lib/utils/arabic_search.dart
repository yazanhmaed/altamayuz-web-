import 'arabic_digits.dart';

final _tashkeel = RegExp('[ؐ-ًؚ-ٰٟۖ-ۭـ]');

/// Folds text for forgiving in-memory search: lowercases, trims, converts
/// Arabic digits to Latin, strips tashkeel/tatweel and unifies letter
/// variants (أ إ آ → ا, ة → ه, ى → ي).
String normalizeForSearch(String input) {
  return normalizeDigits(input)
      .toLowerCase()
      .replaceAll(_tashkeel, '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .trim();
}

/// True when every whitespace-separated word of [query] appears in at least
/// one of [fields]. An empty query matches everything.
bool matchesSearch(String query, Iterable<String> fields) {
  final words = normalizeForSearch(query)
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final haystack = fields.map(normalizeForSearch).toList();
  return words.every((w) => haystack.any((f) => f.contains(w)));
}
