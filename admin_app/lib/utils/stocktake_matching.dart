import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;

import 'arabic_digits.dart';
import 'arabic_search.dart';

/// Pure parsing/matching for the stocktake (جرد) import: no Firestore, no
/// widgets, so [parseStocktakeSheet] can run in an isolate via `compute`
/// and [analyzeStocktake] can be re-run cheaply whenever a review choice
/// changes.

final _wholeNumber = RegExp(r'^-?\d+\.0+$');
final _spaces = RegExp(r'\s+');

/// Comparison-only key: trims, collapses spaces, lowercases Latin, unifies
/// Arabic letter variants, strips tashkeel, converts Arabic digits, and
/// treats "41.0" as "41". Stored values are never rewritten with it.
String normalizeKey(String input) {
  final s = normalizeForSearch(input).replaceAll(_spaces, ' ');
  return _wholeNumber.hasMatch(s) ? s.substring(0, s.indexOf('.')) : s;
}

/// A cell's value as clean display text: numbers lose a trailing ".0",
/// Arabic digits become Latin, surrounding spaces go. Used for values that
/// may be written (new size labels) and for messages.
String cellText(Object? value) {
  if (value == null) return '';
  if (value is int) return value.toString();
  if (value is double) {
    return value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toString();
  }
  final s = normalizeDigits(value.toString().trim()).replaceAll(_spaces, ' ');
  return _wholeNumber.hasMatch(s) ? s.substring(0, s.indexOf('.')) : s;
}

/// Parses a quantity cell. Returns null with [error] set when the value is
/// missing, not a whole number, or negative.
({int? qty, String? error}) parseQuantity(Object? value) {
  num? n;
  if (value is num) {
    n = value;
  } else {
    final text = normalizeDigits((value ?? '').toString().trim());
    if (text.isEmpty) return (qty: null, error: 'الكمية فارغة');
    n = int.tryParse(text) ?? double.tryParse(text);
    if (n == null) return (qty: null, error: 'الكمية «$text» ليست رقمًا');
  }
  if (n != n.truncate()) {
    return (qty: null, error: 'الكمية ${cellText(n)} ليست عددًا صحيحًا');
  }
  if (n < 0) return (qty: null, error: 'الكمية ${cellText(n)} سالبة');
  return (qty: n.toInt(), error: null);
}

/// One data row of the sheet, as raw cell values (String / int / double).
class StocktakeRow {
  /// 1-based spreadsheet row number (the header is row 1).
  final int line;
  final Object? productId;
  final Object? name;
  final Object? color;
  final Object? size;
  final Object? qty;
  final Object? price;
  final Object? category;
  final Object? threshold;

  const StocktakeRow({
    required this.line,
    this.productId,
    this.name,
    this.color,
    this.size,
    this.qty,
    this.price,
    this.category,
    this.threshold,
  });
}

const _headerFields = {
  'اسم المنتج': 'name',
  'اللون': 'color',
  'المقاس': 'size',
  'الكمية': 'qty',
  'السعر': 'price',
  'التصنيف': 'category',
  'حد التنبيه': 'threshold',
  'معرّف المنتج': 'id',
};

/// Positions used when a header is missing: the export's column order.
const _defaultColumns = {
  'name': 0,
  'color': 1,
  'size': 2,
  'qty': 3,
  'price': 4,
  'category': 5,
  'threshold': 6,
};

Object? _cellValue(xls.Data? cell) {
  final v = cell?.value;
  return switch (v) {
    null => null,
    xls.IntCellValue() => v.value,
    xls.DoubleCellValue() => v.value,
    _ => v.toString(),
  };
}

/// Decodes the first sheet of an .xlsx file. Columns are found by header
/// text (so an added or moved `معرّف المنتج` column works), falling back to
/// the export's column order. Fully empty rows are dropped. Top-level so it
/// can run through `compute`.
List<StocktakeRow> parseStocktakeSheet(Uint8List bytes) {
  final book = xls.Excel.decodeBytes(bytes);
  final sheet = book.tables[book.tables.keys.first]!;
  if (sheet.maxRows == 0) return const [];

  final columns = Map<String, int>.from(_defaultColumns);
  final header = sheet.rows.first;
  final headerKeys = {
    for (final e in _headerFields.entries) normalizeKey(e.key): e.value,
  };
  for (var c = 0; c < header.length; c++) {
    final field = headerKeys[normalizeKey(cellText(_cellValue(header[c])))];
    if (field != null) columns[field] = c;
  }

  Object? at(List<xls.Data?> row, String field) {
    final i = columns[field];
    if (i == null || i >= row.length) return null;
    final v = _cellValue(row[i]);
    return v is String && v.trim().isEmpty ? null : v;
  }

  final rows = <StocktakeRow>[];
  for (var r = 1; r < sheet.maxRows; r++) {
    final row = sheet.rows[r];
    final parsed = StocktakeRow(
      line: r + 1,
      productId: at(row, 'id'),
      name: at(row, 'name'),
      color: at(row, 'color'),
      size: at(row, 'size'),
      qty: at(row, 'qty'),
      price: at(row, 'price'),
      category: at(row, 'category'),
      threshold: at(row, 'threshold'),
    );
    if (parsed.productId == null &&
        parsed.name == null &&
        parsed.color == null &&
        parsed.size == null &&
        parsed.qty == null) {
      continue;
    }
    rows.add(parsed);
  }
  return rows;
}

/// The parts of a product the matcher needs.
class StocktakeProduct {
  final String id;
  final String name;
  final String category;
  final double price;
  final int lowStockThreshold;
  final List<String> colors;
  final Map<String, Map<String, int>> stock;

  const StocktakeProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.lowStockThreshold,
    required this.colors,
    required this.stock,
  });

  int get totalQty =>
      stock.values.expand((s) => s.values).fold(0, (a, b) => a + b);
}

enum StocktakeStatus {
  /// Product, color and size all exist.
  matched,

  /// Existing product, but the color or the size is new.
  newVariant,

  /// No product with this id/name.
  unknownProduct,

  /// Several products share the name and none has been picked yet (or the
  /// user chose to skip them).
  ambiguous,

  /// Missing fields, bad quantity, or an earlier duplicate of a later row.
  invalid,
}

class StocktakeLine {
  final StocktakeRow row;
  final StocktakeStatus status;

  /// Normalized file name — groups unknown/ambiguous rows.
  final String nameKey;
  final String fileName;

  /// Resolved product (matched/newVariant only).
  final StocktakeProduct? product;

  /// Stored key when it exists on the product, else the file's clean text.
  final String color;
  final String size;
  final bool isNewColor;

  /// Current quantity (null for a new color/size).
  final int? current;
  final int? newQty;

  /// Why the row is invalid.
  final String? error;

  /// Non-blocking note (e.g. "a later duplicate replaced this").
  final String? warning;

  const StocktakeLine({
    required this.row,
    required this.status,
    required this.nameKey,
    required this.fileName,
    this.product,
    this.color = '',
    this.size = '',
    this.isNewColor = false,
    this.current,
    this.newQty,
    this.error,
    this.warning,
  });

  bool get isChanged => status == StocktakeStatus.matched && newQty != current;

  StocktakeLine _invalid(String message) => StocktakeLine(
        row: row,
        status: StocktakeStatus.invalid,
        nameKey: nameKey,
        fileName: fileName,
        product: product,
        color: color,
        size: size,
        error: message,
      );

  StocktakeLine _withWarning(String message) => StocktakeLine(
        row: row,
        status: status,
        nameKey: nameKey,
        fileName: fileName,
        product: product,
        color: color,
        size: size,
        isNewColor: isNewColor,
        current: current,
        newQty: newQty,
        warning: message,
      );
}

/// Optional price/category/threshold values for one product, taken from the
/// last non-empty cell across its rows; only fields that differ from the
/// product are kept.
class StocktakeMetaUpdate {
  final StocktakeProduct product;
  final double? price;
  final String? category;
  final int? threshold;
  const StocktakeMetaUpdate(this.product,
      {this.price, this.category, this.threshold});

  bool get isEmpty => price == null && category == null && threshold == null;
}

class StocktakeAnalysis {
  final List<StocktakeLine> lines;

  /// Normalized name -> the products sharing it, for names that need a pick.
  final Map<String, List<StocktakeProduct>> ambiguousNames;
  final Map<String, StocktakeMetaUpdate> metaUpdates; // productId -> update

  const StocktakeAnalysis(this.lines, this.ambiguousNames, this.metaUpdates);

  int count(StocktakeStatus s) => lines.where((l) => l.status == s).length;
  int get changedCount => lines.where((l) => l.isChanged).length;
  int get unchangedCount => lines
      .where((l) => l.status == StocktakeStatus.matched && !l.isChanged)
      .length;
}

/// Classifies every row against [products]. [nameChoices] resolves
/// ambiguous names: normalized name -> chosen product id, or '' to skip.
StocktakeAnalysis analyzeStocktake(
  List<StocktakeRow> rows,
  List<StocktakeProduct> products, {
  Map<String, String> nameChoices = const {},
}) {
  final byId = {for (final p in products) p.id: p};
  final byName = <String, List<StocktakeProduct>>{};
  for (final p in products) {
    byName.putIfAbsent(normalizeKey(p.name), () => []).add(p);
  }

  final ambiguousNames = <String, List<StocktakeProduct>>{};
  final lines = <StocktakeLine>[];

  for (final row in rows) {
    final fileName = cellText(row.name);
    final nameKey = normalizeKey(fileName);
    final colorText = cellText(row.color);
    final sizeText = cellText(row.size);
    final idText = cellText(row.productId);

    StocktakeLine invalid(String message) => StocktakeLine(
          row: row,
          status: StocktakeStatus.invalid,
          nameKey: nameKey,
          fileName: fileName,
          color: colorText,
          size: sizeText,
          error: message,
        );

    var product = idText.isEmpty ? null : byId[idText];
    final missing = [
      if (fileName.isEmpty && product == null) 'اسم المنتج',
      if (colorText.isEmpty) 'اللون',
      if (sizeText.isEmpty) 'المقاس',
    ];
    if (missing.isNotEmpty) {
      lines.add(invalid('ناقص: ${missing.join('، ')}'));
      continue;
    }
    final q = parseQuantity(row.qty);
    if (q.error != null) {
      lines.add(invalid(q.error!));
      continue;
    }

    if (product == null) {
      final candidates = byName[nameKey] ?? const [];
      if (candidates.isEmpty) {
        lines.add(StocktakeLine(
          row: row,
          status: StocktakeStatus.unknownProduct,
          nameKey: nameKey,
          fileName: fileName,
          color: colorText,
          size: sizeText,
          newQty: q.qty,
        ));
        continue;
      }
      if (candidates.length > 1) {
        ambiguousNames[nameKey] = candidates;
        final choice = nameChoices[nameKey];
        product = choice == null || choice.isEmpty ? null : byId[choice];
        if (product == null) {
          lines.add(StocktakeLine(
            row: row,
            status: StocktakeStatus.ambiguous,
            nameKey: nameKey,
            fileName: fileName,
            color: colorText,
            size: sizeText,
            newQty: q.qty,
          ));
          continue;
        }
      } else {
        product = candidates.first;
      }
    }

    final colorKey = normalizeKey(colorText);
    final storedColor = <String>{...product.stock.keys, ...product.colors}
        .where((c) => normalizeKey(c) == colorKey)
        .firstOrNull;
    final sizes = storedColor == null ? null : product.stock[storedColor];
    final sizeKey = normalizeKey(sizeText);
    final storedSize =
        sizes?.keys.where((s) => normalizeKey(s) == sizeKey).firstOrNull;

    final isMatched = storedSize != null;
    lines.add(StocktakeLine(
      row: row,
      status: isMatched ? StocktakeStatus.matched : StocktakeStatus.newVariant,
      nameKey: nameKey,
      fileName: fileName,
      product: product,
      color: storedColor ?? colorText,
      size: storedSize ?? sizeText,
      isNewColor: storedColor == null,
      current: isMatched ? sizes![storedSize] : null,
      newQty: q.qty,
    ));
  }

  // Same product/color/size more than once: the last row wins.
  final lastIndex = <String, int>{};
  String keyOf(StocktakeLine l) => l.product != null
      ? '${l.product!.id}|${normalizeKey(l.color)}|${normalizeKey(l.size)}'
      : 'n:${l.nameKey}|${normalizeKey(l.color)}|${normalizeKey(l.size)}';
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].status == StocktakeStatus.invalid) continue;
    final key = keyOf(lines[i]);
    final previous = lastIndex[key];
    if (previous != null) {
      final prevLine = lines[previous].row.line;
      lines[previous] = lines[previous]
          ._invalid('مكرر — تم اعتماد السطر ${lines[i].row.line} بدلًا منه');
      lines[i] =
          lines[i]._withWarning('مكرر مع السطر $prevLine، تم اعتماد هذا السطر');
    }
    lastIndex[key] = i;
  }

  final metaUpdates = <String, StocktakeMetaUpdate>{};
  final metaRaw =
      <String, ({String price, String category, String threshold})>{};
  for (final l in lines) {
    final p = l.product;
    if (p == null || l.status == StocktakeStatus.invalid) continue;
    final prev = metaRaw[p.id] ?? (price: '', category: '', threshold: '');
    final price = cellText(l.row.price);
    final category = cellText(l.row.category);
    final threshold = cellText(l.row.threshold);
    metaRaw[p.id] = (
      price: price.isNotEmpty ? price : prev.price,
      category: category.isNotEmpty ? category : prev.category,
      threshold: threshold.isNotEmpty ? threshold : prev.threshold,
    );
  }
  metaRaw.forEach((id, raw) {
    final p = byId[id]!;
    final price = double.tryParse(raw.price);
    final threshold = int.tryParse(raw.threshold);
    final update = StocktakeMetaUpdate(
      p,
      price: price != null && price >= 0 && price != p.price ? price : null,
      category: raw.category.isNotEmpty && raw.category != p.category
          ? raw.category
          : null,
      threshold: threshold != null &&
              threshold >= 0 &&
              threshold != p.lowStockThreshold
          ? threshold
          : null,
    );
    if (!update.isEmpty) metaUpdates[id] = update;
  });

  return StocktakeAnalysis(lines, ambiguousNames, metaUpdates);
}
