import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../pricing/promotion_pricing.dart';

/// In-memory cache of the promotions that are switched on and not yet ended.
///
/// Loaded once at startup with a plain `get()` (no stream), refreshed every
/// [_refreshEvery] and when the tab/app comes back to the foreground. Listeners
/// are notified when the loaded list changes, and also exactly when a loaded
/// promotion starts or ends, so prices flip without waiting for a refresh.
///
/// Every price on the storefront goes through [PublicProductModel.pricing],
/// which reads [promotions] from here — so cards, detail, cart and checkout
/// always agree. The server re-prices every order anyway.
class PromotionsRepository extends ChangeNotifier {
  static const _refreshEvery = Duration(minutes: 5);
  static const _minForegroundGap = Duration(seconds: 30);

  List<Promotion> _promotions = const [];
  Timer? _refreshTimer;
  Timer? _boundaryTimer;
  AppLifecycleListener? _lifecycle;
  DateTime? _lastLoad;
  bool _loading = false;

  /// Switched-on, not-yet-ended promotions (may include scheduled ones; the
  /// pricing rule checks the start date).
  List<Promotion> get promotions => _promotions;

  /// Promotions running right now.
  List<Promotion> get running {
    final now = DateTime.now();
    return _promotions.where((p) => p.isRunningAt(now)).toList();
  }

  void start() {
    if (_refreshTimer != null) return;
    refresh();
    _refreshTimer = Timer.periodic(_refreshEvery, (_) => refresh());
    _lifecycle = AppLifecycleListener(onResume: () {
      final last = _lastLoad;
      if (last == null || DateTime.now().difference(last) > _minForegroundGap) {
        refresh();
      }
    });
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('promotions')
          .where('isActive', isEqualTo: true)
          .where('endAt', isGreaterThan: Timestamp.now())
          .get();
      final list = <Promotion>[];
      for (final doc in snap.docs) {
        final p = _fromDoc(doc.id, doc.data());
        if (p != null) list.add(p);
      }
      _lastLoad = DateTime.now();
      if (!_sameAs(list)) {
        _promotions = List.unmodifiable(list);
        notifyListeners();
      }
      _scheduleBoundary();
    } catch (e) {
      // Keep the last good cache; the next tick retries.
      debugPrint('promotions: refresh failed: $e');
    } finally {
      _loading = false;
    }
  }

  /// Wakes up at the next start/end date among the loaded promotions so a
  /// promotion appears/disappears on time without a refetch.
  void _scheduleBoundary() {
    _boundaryTimer?.cancel();
    final now = DateTime.now();
    DateTime? next;
    for (final p in _promotions) {
      for (final t in [p.startAt, p.endAt]) {
        if (t.isAfter(now) && (next == null || t.isBefore(next))) next = t;
      }
    }
    if (next == null) return;
    // Timers longer than ~24 days overflow on web; the periodic refresh
    // reschedules long before then anyway.
    var wait = next.difference(now) + const Duration(milliseconds: 500);
    if (wait > const Duration(days: 1)) wait = const Duration(days: 1);
    _boundaryTimer = Timer(wait, () {
      notifyListeners();
      _scheduleBoundary();
    });
  }

  bool _sameAs(List<Promotion> other) {
    if (other.length != _promotions.length) return false;
    for (var i = 0; i < other.length; i++) {
      final a = other[i], b = _promotions[i];
      if (a.id != b.id ||
          a.name != b.name ||
          a.amountOff != b.amountOff ||
          a.percent != b.percent ||
          a.isActive != b.isActive ||
          a.startAt != b.startAt ||
          a.endAt != b.endAt ||
          a.bannerText != b.bannerText ||
          a.productIds.length != b.productIds.length ||
          !a.productIds.every(b.productIds.contains)) {
        return false;
      }
    }
    return true;
  }

  static Promotion? _fromDoc(String id, Map<String, dynamic> d) {
    final startAt = d['startAt'];
    final endAt = d['endAt'];
    if (startAt is! Timestamp || endAt is! Timestamp) return null;
    // amountOff (JOD) is current; percent is read only for legacy docs.
    final amountOff = (d['amountOff'] as num?)?.toDouble();
    final percent = (d['percent'] as num?)?.toDouble();
    if (amountOff == null && percent == null) return null;
    final ids = d['productIds'];
    final banner = (d['bannerText'] as String?)?.trim();
    return Promotion(
      id: id,
      name: d['name'] as String? ?? '',
      amountOff: amountOff,
      percent: percent,
      productIds: ids is List
          ? ids.whereType<String>().take(kMaxPromoProducts).toList()
          : const [],
      startAt: startAt.toDate(),
      endAt: endAt.toDate(),
      isActive: d['isActive'] == true,
      bannerText: (banner == null || banner.isEmpty) ? null : banner,
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _boundaryTimer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}

final promotionsRepository = PromotionsRepository();
