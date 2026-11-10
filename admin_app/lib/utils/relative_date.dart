/// Arabic relative date, e.g. "اليوم", "أمس", "قبل 3 أيام", "قبل 12 يوماً",
/// "قبل شهرين", "قبل سنة". Counts calendar days, not 24h blocks.
String relativeDateAr(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = today.difference(day).inDays;

  if (days <= 0) return 'اليوم';
  if (days == 1) return 'أمس';
  if (days < 30) return 'قبل ${_count(days, 'يوم', 'يومين', 'أيام', 'يوماً')}';
  final months = days ~/ 30;
  if (months < 12) {
    return 'قبل ${_count(months, 'شهر', 'شهرين', 'أشهر', 'شهراً')}';
  }
  final years = days ~/ 365;
  return 'قبل ${_count(years < 1 ? 1 : years, 'سنة', 'سنتين', 'سنوات', 'سنة')}';
}

/// Arabic number–noun agreement: 1 → singular, 2 → dual, 3–10 → plural,
/// 11+ → accusative singular.
String _count(int n, String one, String two, String few, String many) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n <= 10) return '$n $few';
  return '$n $many';
}
