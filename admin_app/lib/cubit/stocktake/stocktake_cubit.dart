import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/product/product_model.dart';
import '../../utils/stocktake_matching.dart';
import 'stocktake_state.dart';

/// One stock value to SET (never increment) on a product.
class _PlannedStock {
  final String color;
  final String size;
  final int qty;
  const _PlannedStock(this.color, this.size, this.qty);
}

/// Everything one product's transaction writes.
class _ProductPlan {
  final String productId;
  final String name;
  final List<_PlannedStock> stock;
  final StocktakeMetaUpdate? meta;
  const _ProductPlan(this.productId, this.name, this.stock, this.meta);
}

class StocktakeFailure {
  final String productName;
  final String error;
  const StocktakeFailure(this.productName, this.error);
}

/// Running totals of one stocktake (kept across retries).
class StocktakeResult {
  int updatedSizes = 0;
  int updatedProducts = 0;
  List<StocktakeFailure> failures = const [];
}

/// A `stocktakes/{id}` audit record, for the history list.
class StocktakeRecord {
  final String id;
  final DateTime? createdAt;
  final String fileName;
  final String appliedBy;
  final String status;
  final int updatedSizes;
  final int updatedProducts;
  final DateTime? undoneAt;
  final int undoRestored;
  final int undoSkipped;

  const StocktakeRecord({
    required this.id,
    required this.createdAt,
    required this.fileName,
    required this.appliedBy,
    required this.status,
    required this.updatedSizes,
    required this.updatedProducts,
    required this.undoneAt,
    required this.undoRestored,
    required this.undoSkipped,
  });

  factory StocktakeRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return StocktakeRecord(
      id: doc.id,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      fileName: d['fileName'] as String? ?? '',
      appliedBy: d['appliedBy'] as String? ?? '',
      status: d['status'] as String? ?? '',
      updatedSizes: (d['updatedSizes'] as num?)?.toInt() ?? 0,
      updatedProducts: (d['updatedProducts'] as num?)?.toInt() ?? 0,
      undoneAt: (d['undoneAt'] as Timestamp?)?.toDate(),
      undoRestored: (d['undoRestored'] as num?)?.toInt() ?? 0,
      undoSkipped: (d['undoSkipped'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `stock.<color>.<size>` update path; keys holding a path character
/// can't be addressed this way, so that product fails with a message.
String _stockPath(String color, [String? size]) {
  final parts = [color, if (size != null) size];
  if (parts.any((p) => p.contains(RegExp(r'[.~*/\[\]]')))) {
    throw _StocktakeException(
        'اللون/المقاس «${parts.join(' / ')}» يحتوي على رمز غير مدعوم.');
  }
  return ['stock', ...parts].join('.');
}

class _StocktakeException implements Exception {
  final String message;
  const _StocktakeException(this.message);
  @override
  String toString() => message;
}

/// Stocktake (جرد) import: the file holds FINAL counts that replace current
/// stock of existing products. Never creates products. Each product is
/// applied in its own transaction (read live doc → one `tx.update` of
/// `stock.<color>.<size>` = count) together with its audit entry under
/// `stocktakes/{id}/changes/{productId}`, so the log always matches what
/// was written and can be undone.
class StocktakeCubit extends Cubit<StocktakeState> {
  StocktakeCubit() : super(StocktakeInitial());

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _chunkSize = 10;

  // ---- review state ----
  String fileName = '';
  DateTime? fileModifiedAt;
  List<StocktakeRow> _rows = const [];
  List<StocktakeProduct> _products = const [];
  StocktakeAnalysis? analysis;

  /// Normalized name -> chosen product id ('' = skip) for shared names.
  final Map<String, String> nameChoices = {};

  /// Sheet lines of new-color/size rows the user chose to add.
  final Set<int> addNewVariantLines = {};

  /// Also write price/category/threshold from the file (off by default).
  bool updateMeta = false;

  // ---- apply state ----
  bool isApplying = false;
  String? _stocktakeId;
  List<_ProductPlan> _failedPlans = const [];
  StocktakeResult? lastResult;

  // ---- history ----
  List<StocktakeRecord> history = const [];
  String? undoingId;

  bool get hasReview => analysis != null;

  /// Picks an .xlsx file and builds the review.
  Future<void> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) {
      emit(StocktakeError('لم يتم اختيار ملف.'));
      return;
    }
    DateTime? modified;
    if (!kIsWeb && file.path != null) {
      try {
        modified = await File(file.path!).lastModified();
      } catch (_) {}
    }
    await loadFile(file.bytes!, file.name, modifiedAt: modified);
  }

  /// Parses [bytes] off the UI thread, loads live products and classifies.
  Future<void> loadFile(Uint8List bytes, String name,
      {DateTime? modifiedAt}) async {
    emit(StocktakeParsing());
    try {
      final rows = await compute(parseStocktakeSheet, bytes);
      if (rows.isEmpty) {
        emit(StocktakeError('لم يتم العثور على بيانات في الملف.'));
        return;
      }
      _clearReview();
      fileName = name;
      fileModifiedAt = modifiedAt;
      _rows = rows;
      _products = await _loadProducts();
      _analyze();
      emit(StocktakeReviewReady());
    } catch (e) {
      emit(StocktakeError('فشل تحليل الملف: $e'));
    }
  }

  /// Re-reads products (e.g. after one was created from the review).
  Future<void> reloadProducts() async {
    if (_rows.isEmpty) return;
    try {
      _products = await _loadProducts();
      _analyze();
      emit(StocktakeReviewReady());
    } catch (e) {
      emit(StocktakeError(e.toString()));
    }
  }

  Future<List<StocktakeProduct>> _loadProducts() async {
    final snap = await _db.collection('products').get();
    return snap.docs.map((d) {
      final p = ProductModel.fromMap({...d.data(), 'id': d.id});
      return StocktakeProduct(
        id: p.id,
        name: p.name,
        category: p.category,
        price: p.price,
        lowStockThreshold: p.lowStockThreshold,
        colors: p.colors,
        stock: p.stock,
      );
    }).toList();
  }

  void _analyze() {
    analysis = analyzeStocktake(_rows, _products, nameChoices: nameChoices);
  }

  void setNameChoice(String nameKey, String productId) {
    nameChoices[nameKey] = productId;
    _analyze();
    emit(StocktakeReviewReady());
  }

  void setAddNewVariant(int line, bool add) {
    add ? addNewVariantLines.add(line) : addNewVariantLines.remove(line);
    emit(StocktakeReviewReady());
  }

  void setAllNewVariants(bool add) {
    addNewVariantLines.clear();
    if (add) {
      addNewVariantLines.addAll(analysis!.lines
          .where((l) => l.status == StocktakeStatus.newVariant)
          .map((l) => l.row.line));
    }
    emit(StocktakeReviewReady());
  }

  void setUpdateMeta(bool value) {
    updateMeta = value;
    emit(StocktakeReviewReady());
  }

  bool _isApproved(StocktakeLine l) =>
      l.status == StocktakeStatus.matched ||
      (l.status == StocktakeStatus.newVariant &&
          addNewVariantLines.contains(l.row.line));

  /// Changes as seen in the review (the confirm dialog's count).
  int get pendingChangeCount {
    final a = analysis;
    if (a == null) return 0;
    var n = a.lines
        .where((l) =>
            l.isChanged ||
            (l.status == StocktakeStatus.newVariant && _isApproved(l)))
        .length;
    if (updateMeta) n += a.metaUpdates.length;
    return n;
  }

  /// Every approved row, grouped by product. Unchanged rows are included on
  /// purpose: the transaction compares against LIVE stock, so a size sold
  /// since the export is still reset to the file's count.
  List<_ProductPlan> _buildPlans() {
    final a = analysis!;
    final byProduct = <String, List<_PlannedStock>>{};
    final names = <String, String>{};
    for (final l in a.lines) {
      if (!_isApproved(l)) continue;
      byProduct
          .putIfAbsent(l.product!.id, () => [])
          .add(_PlannedStock(l.color, l.size, l.newQty!));
      names[l.product!.id] = l.product!.name;
    }
    if (updateMeta) {
      for (final m in a.metaUpdates.values) {
        byProduct.putIfAbsent(m.product.id, () => []);
        names[m.product.id] = m.product.name;
      }
    }
    return [
      for (final e in byProduct.entries)
        _ProductPlan(e.key, names[e.key]!, e.value,
            updateMeta ? a.metaUpdates[e.key] : null),
    ];
  }

  Future<void> apply() async {
    if (isApplying || analysis == null) return;
    final plans = _buildPlans();
    if (plans.isEmpty) {
      emit(StocktakeError('لا توجد تغييرات لتطبيقها.'));
      return;
    }
    isApplying = true;
    emit(StocktakeApplying(0, plans.length));

    final a = analysis!;
    final user = FirebaseAuth.instance.currentUser;
    final header = _db.collection('stocktakes').doc();
    try {
      // Written first: if it can't be saved, no stock is touched.
      await header.set({
        'createdAt': FieldValue.serverTimestamp(),
        'fileName': fileName,
        'fileModifiedAt': fileModifiedAt,
        'mode': 'stocktake',
        'appliedBy': user?.email ?? user?.uid ?? '',
        'status': 'applying',
        'updateMeta': updateMeta,
        'summary': {
          'rows': a.lines.length,
          'matched': a.count(StocktakeStatus.matched),
          'changed': a.changedCount,
          'unchanged': a.unchangedCount,
          'newVariants': a.count(StocktakeStatus.newVariant),
          'newVariantsAdded': addNewVariantLines.length,
          'unknownProducts': a.count(StocktakeStatus.unknownProduct),
          'ambiguous': a.count(StocktakeStatus.ambiguous),
          'invalid': a.count(StocktakeStatus.invalid),
        },
        'updatedSizes': 0,
        'updatedProducts': 0,
      });
    } catch (e) {
      isApplying = false;
      emit(StocktakeError('تعذّر إنشاء سجل الجرد، لم يتم تغيير أي مخزون.\n$e'));
      return;
    }
    _stocktakeId = header.id;
    lastResult = StocktakeResult();
    await _run(plans);
  }

  Future<void> retryFailed() async {
    if (isApplying || _stocktakeId == null || _failedPlans.isEmpty) return;
    isApplying = true;
    final plans = _failedPlans;
    emit(StocktakeApplying(0, plans.length));
    await _run(plans);
  }

  /// Applies [plans] [_chunkSize] at a time; a failed product doesn't stop
  /// the others and is kept for [retryFailed].
  Future<void> _run(List<_ProductPlan> plans) async {
    final result = lastResult!;
    final failed = <_ProductPlan>[];
    final failures = <StocktakeFailure>[];
    var sizes = 0, productsUpdated = 0, done = 0;

    for (var i = 0; i < plans.length; i += _chunkSize) {
      final chunk = plans.skip(i).take(_chunkSize).toList();
      final outcomes = await Future.wait(chunk.map((p) async {
        try {
          return (plan: p, changes: await _applyPlan(p), error: null);
        } catch (e) {
          return (plan: p, changes: 0, error: e.toString());
        }
      }));
      for (final o in outcomes) {
        if (o.error != null) {
          failed.add(o.plan);
          failures.add(StocktakeFailure(o.plan.name, o.error!));
        } else if (o.changes > 0) {
          sizes += o.changes;
          productsUpdated++;
        }
      }
      done += chunk.length;
      emit(StocktakeApplying(done, plans.length));
    }

    result.updatedSizes += sizes;
    result.updatedProducts += productsUpdated;
    result.failures = failures;
    _failedPlans = failed;
    try {
      await _db.collection('stocktakes').doc(_stocktakeId).update({
        'status': failed.isEmpty ? 'applied' : 'partial',
        'updatedSizes': result.updatedSizes,
        'updatedProducts': result.updatedProducts,
        'failedProducts': [for (final f in failures) f.productName],
      });
    } catch (_) {
      // The per-product change entries are already saved with each write.
    }

    if (failed.isEmpty) _clearReview();
    isApplying = false;
    emit(StocktakeApplied());
  }

  /// One transaction: read the live product, SET each differing size to the
  /// file's count, and save the before/after log next to it. Returns the
  /// number of stock values changed.
  Future<int> _applyPlan(_ProductPlan plan) {
    final productRef = _db.collection('products').doc(plan.productId);
    final logRef = _db
        .collection('stocktakes')
        .doc(_stocktakeId)
        .collection('changes')
        .doc(plan.productId);

    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(productRef);
      if (!snap.exists) {
        throw const _StocktakeException('المنتج لم يعد موجودًا.');
      }
      final data = snap.data()!;
      final liveStock = data['stock'] as Map? ?? const {};
      final liveColors = List<String>.from(data['colors'] as List? ?? const []);

      final update = <String, Object?>{};
      final changes = <Map<String, Object?>>[];
      final addedColors = <String>{};
      var stockChanges = 0;
      for (final s in plan.stock) {
        final sizes = liveStock[s.color];
        final before = sizes is Map ? (sizes[s.size] as num?)?.toInt() : null;
        if (before == s.qty) continue;
        final isNewColor = sizes is! Map && !liveColors.contains(s.color);
        update[_stockPath(s.color, s.size)] = s.qty;
        if (!liveColors.contains(s.color)) addedColors.add(s.color);
        changes.add({
          'field': 'stock',
          'color': s.color,
          'size': s.size,
          'before': before,
          'after': s.qty,
          'newColor': isNewColor,
        });
        stockChanges++;
      }

      final meta = plan.meta;
      if (meta != null) {
        void setField(String field, Object? value) {
          if (value == null || data[field] == value) return;
          update[field] = value;
          changes.add({'field': field, 'before': data[field], 'after': value});
        }

        setField('price', meta.price);
        setField('category', meta.category);
        setField('lowStockThreshold', meta.threshold);
      }

      if (update.isEmpty) return 0;
      if (addedColors.isNotEmpty) {
        update['colors'] = FieldValue.arrayUnion(addedColors.toList());
      }
      update['updatedAt'] = DateTime.now().toIso8601String();
      tx.update(productRef, update);
      tx.set(logRef, {
        'productId': plan.productId,
        'name': data['name'] ?? plan.name,
        'items': changes,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return stockChanges;
    });
  }

  void _clearReview() {
    _rows = const [];
    _products = const [];
    analysis = null;
    nameChoices.clear();
    addNewVariantLines.clear();
    updateMeta = false;
    fileName = '';
    fileModifiedAt = null;
  }

  /// Leaves the review (and any finished result) behind.
  void reset() {
    if (isApplying) return;
    _clearReview();
    _stocktakeId = null;
    _failedPlans = const [];
    lastResult = null;
    emit(StocktakeInitial());
  }

  // ---------------------------------------------------------------------
  // History & undo
  // ---------------------------------------------------------------------

  Future<void> loadHistory() async {
    emit(StocktakeHistoryLoading());
    try {
      final snap = await _db
          .collection('stocktakes')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      history = snap.docs.map(StocktakeRecord.fromDoc).toList();
      emit(StocktakeHistoryLoaded());
    } catch (e) {
      emit(StocktakeError('تعذّر تحميل سجل الجرد: $e'));
    }
  }

  /// Restores each logged `before` value, per product in one transaction,
  /// only where the live value still equals the logged `after`; anything
  /// changed since is skipped and counted.
  Future<void> undo(String stocktakeId) async {
    if (undoingId != null) return;
    undoingId = stocktakeId;
    emit(StocktakeHistoryLoaded());

    final header = _db.collection('stocktakes').doc(stocktakeId);
    var restored = 0, skipped = 0;
    final failedNames = <String>[];
    try {
      final logs = await header.collection('changes').get();
      for (final log in logs.docs) {
        if (log.data()['undoneAt'] != null) continue;
        try {
          final r = await _undoProduct(log.reference, log.data());
          restored += r.restored;
          skipped += r.skipped;
        } catch (_) {
          failedNames.add(log.data()['name'] as String? ?? log.id);
        }
      }
      await header.update({
        if (failedNames.isEmpty) 'undoneAt': FieldValue.serverTimestamp(),
        'undoRestored': FieldValue.increment(restored),
        'undoSkipped': FieldValue.increment(skipped),
      });
    } catch (e) {
      undoingId = null;
      emit(StocktakeError('فشل التراجع: $e'));
      return;
    }
    undoingId = null;
    await loadHistory();
    final parts = [
      'تمت استعادة $restored قيمة',
      if (skipped > 0) 'وتخطي $skipped تغيّرت بعد الجرد',
      if (failedNames.isNotEmpty)
        '— فشل: ${failedNames.join('، ')} (أعد المحاولة)',
    ];
    emit(StocktakeUndoDone(parts.join(' ')));
  }

  Future<({int restored, int skipped})> _undoProduct(
    DocumentReference<Map<String, dynamic>> logRef,
    Map<String, dynamic> log,
  ) {
    final items = List<Map<String, dynamic>>.from(
        (log['items'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)));
    final productRef =
        _db.collection('products').doc(log['productId'] as String);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(productRef);
      if (!snap.exists) {
        tx.update(logRef, {
          'undoneAt': FieldValue.serverTimestamp(),
          'undoSkipped': items.length
        });
        return (restored: 0, skipped: items.length);
      }
      final data = snap.data()!;
      final liveStock = data['stock'] as Map? ?? const {};
      final update = <String, Object?>{};
      final removedSizes = <String, Set<String>>{};
      final newColors = <String>{};
      var restored = 0, skipped = 0;

      for (final item in items) {
        final field = item['field'] as String? ?? 'stock';
        final before = item['before'];
        final after = item['after'];
        if (field != 'stock') {
          if (data[field] != after) {
            skipped++;
            continue;
          }
          update[field] = before ?? FieldValue.delete();
          restored++;
          continue;
        }
        final color = item['color'] as String;
        final size = item['size'] as String;
        final sizes = liveStock[color];
        final current = sizes is Map ? (sizes[size] as num?)?.toInt() : null;
        if (current != after) {
          skipped++;
          continue;
        }
        if (before == null) {
          update[_stockPath(color, size)] = FieldValue.delete();
          removedSizes.putIfAbsent(color, () => {}).add(size);
          if (item['newColor'] == true) newColors.add(color);
        } else {
          update[_stockPath(color, size)] = before;
        }
        restored++;
      }

      // A color the stocktake added goes away once none of its sizes remain.
      final removedColors = <String>[];
      for (final color in newColors) {
        final remaining = (liveStock[color] as Map? ?? const {})
            .keys
            .where((s) => !removedSizes[color]!.contains(s));
        if (remaining.isEmpty) {
          for (final size in removedSizes[color]!) {
            update.remove(_stockPath(color, size));
          }
          update[_stockPath(color)] = FieldValue.delete();
          removedColors.add(color);
        }
      }
      if (removedColors.isNotEmpty) {
        update['colors'] = FieldValue.arrayRemove(removedColors);
      }

      if (update.isNotEmpty) {
        update['updatedAt'] = DateTime.now().toIso8601String();
        tx.update(productRef, update);
      }
      tx.update(logRef,
          {'undoneAt': FieldValue.serverTimestamp(), 'undoSkipped': skipped});
      return (restored: restored, skipped: skipped);
    });
  }
}
