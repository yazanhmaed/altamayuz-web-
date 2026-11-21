import 'dart:typed_data';

import 'package:altamayuz_admin/utils/stocktake_matching.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';

StocktakeProduct product(
  String id,
  String name,
  Map<String, Map<String, int>> stock, {
  double price = 25,
  String category = 'رسمي',
  int threshold = 1,
}) =>
    StocktakeProduct(
      id: id,
      name: name,
      category: category,
      price: price,
      lowStockThreshold: threshold,
      colors: stock.keys.toList(),
      stock: stock,
    );

int _line = 1;
StocktakeRow row(Object? name, Object? color, Object? size, Object? qty,
        {Object? id, Object? price, Object? category, Object? threshold}) =>
    StocktakeRow(
      line: ++_line,
      productId: id,
      name: name,
      color: color,
      size: size,
      qty: qty,
      price: price,
      category: category,
      threshold: threshold,
    );

void main() {
  final shoe = product('p930', '930', {
    'BLACK': {'40': 0, '41': 1},
    'BROWN': {'40': 2},
  });

  test('normalizeKey folds Arabic letters, case, spaces and whole decimals',
      () {
    expect(normalizeKey('  أحمر   غامق '), normalizeKey('احمر غامق'));
    expect(normalizeKey('حذاءُ رياضة'), normalizeKey('حذاء رياضه'));
    expect(normalizeKey('مقهى'), normalizeKey('مقهي'));
    expect(normalizeKey('Black'), 'black');
    expect(normalizeKey('41.0'), '41');
    expect(normalizeKey('٤١'), '41');
  });

  test('quantities accept int/double/text and reject bad values', () {
    expect(parseQuantity(3).qty, 3);
    expect(parseQuantity(3.0).qty, 3);
    expect(parseQuantity('٧').qty, 7);
    expect(parseQuantity('2.0').qty, 2);
    expect(parseQuantity(2.5).error, isNotNull);
    expect(parseQuantity(-1).error, isNotNull);
    expect(parseQuantity('abc').error, isNotNull);
    expect(parseQuantity(null).error, isNotNull);
  });

  test('matches numeric names/sizes and computes changes', () {
    final a = analyzeStocktake([
      row(930, 'black', 41.0, 4),
      row('930', 'BLACK', '40', 0),
      row(' 930 ', 'Brown', 40, '٢'),
    ], [
      shoe
    ]);
    expect(a.count(StocktakeStatus.matched), 3);
    expect(a.changedCount, 1);
    expect(a.unchangedCount, 2);
    final changed = a.lines.firstWhere((l) => l.isChanged);
    expect((changed.color, changed.size, changed.current, changed.newQty),
        ('BLACK', '41', 1, 4));
  });

  test('new color/size, unknown product, invalid rows', () {
    final a = analyzeStocktake([
      row('930', 'RED', '40', 1),
      row('930', 'BLACK', '46', 1),
      row('999', 'BLACK', '40', 1),
      row('930', '', '40', 1),
      row('930', 'BLACK', '40', -2),
    ], [
      shoe
    ]);
    expect(a.lines.map((l) => l.status), [
      StocktakeStatus.newVariant,
      StocktakeStatus.newVariant,
      StocktakeStatus.unknownProduct,
      StocktakeStatus.invalid,
      StocktakeStatus.invalid,
    ]);
    expect(a.lines[0].isNewColor, isTrue);
    expect(a.lines[1].isNewColor, isFalse);
    expect(a.lines[1].color, 'BLACK');
  });

  test('duplicate rows: the last one wins with a warning', () {
    final a = analyzeStocktake([
      row('930', 'BLACK', '41', 5),
      row('930', 'black', '41.0', 6),
    ], [
      shoe
    ]);
    expect(a.lines[0].status, StocktakeStatus.invalid);
    expect(a.lines[1].status, StocktakeStatus.matched);
    expect(a.lines[1].newQty, 6);
    expect(a.lines[1].warning, isNotNull);
  });

  test('shared names are ambiguous until a product is picked', () {
    final copy = product('dup', '930', {
      'BLACK': {'41': 9},
    });
    final rows = [row('930', 'BLACK', '41', 2)];
    var a = analyzeStocktake(rows, [shoe, copy]);
    expect(a.lines.single.status, StocktakeStatus.ambiguous);
    expect(a.ambiguousNames['930']!.map((p) => p.id), ['p930', 'dup']);

    a = analyzeStocktake(rows, [shoe, copy], nameChoices: {'930': 'dup'});
    expect(a.lines.single.product!.id, 'dup');
    expect(a.lines.single.current, 9);

    a = analyzeStocktake(rows, [shoe, copy], nameChoices: {'930': ''});
    expect(a.lines.single.status, StocktakeStatus.ambiguous);
  });

  test('product id column wins over the name', () {
    final copy = product('dup', '930', {
      'BLACK': {'41': 9},
    });
    final a = analyzeStocktake(
        [row('renamed', 'BLACK', '41', 2, id: 'dup')], [shoe, copy]);
    expect(a.lines.single.status, StocktakeStatus.matched);
    expect(a.lines.single.product!.id, 'dup');
  });

  test('price/category/threshold differences are collected per product', () {
    final a = analyzeStocktake([
      row('930', 'BLACK', '41', 1, price: '25', category: 'رسمي', threshold: 1),
      row('930', 'BLACK', '40', 0,
          price: 30, category: 'رياضي', threshold: '2'),
    ], [
      shoe
    ]);
    final m = a.metaUpdates['p930']!;
    expect((m.price, m.category, m.threshold), (30.0, 'رياضي', 2));
  });

  test('parses columns by header, including a moved product id column', () {
    final book = xls.Excel.createExcel();
    final sheet = book['Sheet1'];
    sheet.appendRow([
      xls.TextCellValue('معرّف المنتج'),
      xls.TextCellValue('اسم المنتج'),
      xls.TextCellValue('اللون'),
      xls.TextCellValue('المقاس'),
      xls.TextCellValue('الكمية'),
    ]);
    sheet.appendRow([
      xls.TextCellValue('p930'),
      const xls.IntCellValue(930),
      xls.TextCellValue('BLACK'),
      const xls.DoubleCellValue(41.0),
      xls.TextCellValue('٤'),
    ]);
    sheet.appendRow([null, null, null, null, null]);
    final rows = parseStocktakeSheet(Uint8List.fromList(book.encode()!));
    expect(rows, hasLength(1));
    final a = analyzeStocktake(rows, [shoe]);
    expect(a.lines.single.status, StocktakeStatus.matched);
    expect((a.lines.single.size, a.lines.single.newQty), ('41', 4));
  });
}
