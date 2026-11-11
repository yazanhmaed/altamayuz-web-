import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/promotion/promotion_firestore.dart';
import '../../utils/promotion_pricing.dart';

class PromotionsState {
  final bool loading;
  final String? error;

  /// All promotions, newest start date first.
  final List<Promotion> promotions;

  /// True while a write (save, pause, duplicate, delete) is in flight.
  final bool busy;

  /// One-shot snackbar text.
  final String? message;

  const PromotionsState({
    this.loading = false,
    this.error,
    this.promotions = const [],
    this.busy = false,
    this.message,
  });

  PromotionsState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<Promotion>? promotions,
    bool? busy,
    String? message,
  }) {
    return PromotionsState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      promotions: promotions ?? this.promotions,
      busy: busy ?? this.busy,
      // Messages are one-shot: never carried into the next state.
      message: message,
    );
  }
}

/// Owner-side CRUD for `promotions/{id}`. The list is small (a shop runs a
/// handful of promotions), so it is one plain `get()`, not paginated.
class PromotionsCubit extends Cubit<PromotionsState> {
  PromotionsCubit() : super(const PromotionsState());

  final _col = FirebaseFirestore.instance.collection('promotions');
  bool _loaded = false;

  /// Loads once; later calls are no-ops unless [refresh] is set.
  Future<void> load({bool refresh = false}) async {
    if (_loaded && !refresh) return;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final snap = await _col.orderBy('startAt', descending: true).get();
      final list = <Promotion>[];
      for (final d in snap.docs) {
        final p = promotionFromDoc(d.id, d.data());
        if (p != null) list.add(p);
      }
      _loaded = true;
      emit(state.copyWith(loading: false, promotions: list, clearError: true));
    } catch (e) {
      emit(state.copyWith(loading: false, error: 'تعذّر تحميل العروض: $e'));
    }
  }

  /// Creates (id == null) or updates a promotion. Returns true on success.
  Future<bool> save(Promotion draft, {String? id}) async {
    emit(state.copyWith(busy: true));
    try {
      final now = FieldValue.serverTimestamp();
      final banner = draft.bannerText?.trim() ?? '';
      if (id == null) {
        await _col.add({
          ...promotionFields(draft),
          if (banner.isNotEmpty) 'bannerText': banner,
          'createdAt': now,
          'updatedAt': now,
        });
      } else {
        await _col.doc(id).update({
          ...promotionFields(draft),
          // Saving with an amount converts a legacy percentage promotion.
          if (draft.amountOff != null) 'percent': FieldValue.delete(),
          'bannerText': banner.isNotEmpty ? banner : FieldValue.delete(),
          'updatedAt': now,
        });
      }
      await load(refresh: true);
      emit(state.copyWith(busy: false, message: 'تم حفظ العرض.'));
      return true;
    } catch (e) {
      emit(state.copyWith(busy: false, message: 'تعذّر حفظ العرض: $e'));
      return false;
    }
  }

  Future<void> setActive(Promotion p, bool active) async {
    await _write(
      () => _col.doc(p.id).update({
        'isActive': active,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      active ? 'تم استئناف العرض.' : 'تم إيقاف العرض.',
    );
  }

  /// Copies a promotion as a new, paused one so it never goes live by
  /// accident; the owner edits its dates and switches it on.
  Future<void> duplicate(Promotion p) async {
    final now = FieldValue.serverTimestamp();
    await _write(
      () => _col.add({
        ...promotionFields(Promotion(
          id: '',
          name: '${p.name} (نسخة)',
          amountOff: p.amountOff,
          percent: p.percent,
          productIds: p.productIds,
          startAt: p.startAt,
          endAt: p.endAt,
          isActive: false,
        )),
        if (p.bannerText != null) 'bannerText': p.bannerText,
        'createdAt': now,
        'updatedAt': now,
      }),
      'تم إنشاء نسخة متوقفة من العرض.',
    );
  }

  Future<void> delete(Promotion p) async {
    await _write(() => _col.doc(p.id).delete(), 'تم حذف العرض.');
  }

  Future<void> _write(Future<void> Function() op, String success) async {
    emit(state.copyWith(busy: true));
    try {
      await op();
      await load(refresh: true);
      emit(state.copyWith(busy: false, message: success));
    } catch (e) {
      emit(state.copyWith(busy: false, message: 'تعذّرت العملية: $e'));
    }
  }
}
