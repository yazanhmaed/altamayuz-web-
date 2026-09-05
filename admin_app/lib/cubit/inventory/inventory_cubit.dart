import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/product/product_model.dart';
import 'inventory_state.dart';

/// One (size -> quantity) row inside a color's stock table, used by the
/// add/edit-product form.
class SizeQtyRow {
  final TextEditingController sizeCtrl;
  final TextEditingController qtyCtrl;

  SizeQtyRow({String size = '', String qty = ''})
    : sizeCtrl = TextEditingController(text: size),
      qtyCtrl = TextEditingController(text: qty);

  void dispose() {
    sizeCtrl.dispose();
    qtyCtrl.dispose();
  }
}

/// One color row inside the add/edit-product form: a color name, its size
/// table, and (optionally) an already-uploaded image URL.
class ColorFormRow {
  final TextEditingController colorCtrl;
  final List<SizeQtyRow> sizes;
  String? existingImageUrl;

  ColorFormRow({String color = '', this.existingImageUrl})
    : colorCtrl = TextEditingController(text: color),
      sizes = [SizeQtyRow()];

  void dispose() {
    colorCtrl.dispose();
    for (final s in sizes) {
      s.dispose();
    }
  }
}

/// One row inside the restock-only form: color + size + quantity to add.
class RestockRowControllers {
  final TextEditingController colorCtrl;
  final TextEditingController sizeCtrl;
  final TextEditingController qtyCtrl;

  RestockRowControllers({String? color, String? size})
    : colorCtrl = TextEditingController(text: color ?? ''),
      sizeCtrl = TextEditingController(text: size ?? ''),
      qtyCtrl = TextEditingController();

  void dispose() {
    colorCtrl.dispose();
    sizeCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class InventoryCubit extends Cubit<InventoryState> {
  InventoryCubit() : super(InventoryInitial());

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<ProductModel> products = [];
  bool _hasFetched = false;

  // ---- add/edit product form state ----
  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final lowStockCtrl = TextEditingController(text: '1');
  final List<ColorFormRow> colorRows = [ColorFormRow()];
  final Map<String, XFile?> pendingColorImages = {}; // color -> newly picked, not yet uploaded
  bool isActive = true;
  bool isFeatured = false;
  ProductModel? editingProduct;

  // ---- restock-only form state ----
  ProductModel? restockProduct;
  final List<RestockRowControllers> restockRows = [RestockRowControllers()];

  Future<void> fetchProducts({bool refresh = false}) async {
    if (_hasFetched && !refresh) {
      emit(InventoryLoaded(products));
      return;
    }
    emit(InventoryLoading());
    try {
      final snap = await _db.collection('products').orderBy('name').get();
      products = snap.docs.map((d) => ProductModel.fromMap(d.data())).toList();
      _hasFetched = true;
      emit(InventoryLoaded(products));
    } catch (e) {
      emit(InventoryError(e.toString()));
    }
  }

  Future<void> reloadSingle(String productId) async {
    final doc = await _db.collection('products').doc(productId).get();
    if (!doc.exists) return;
    final updated = ProductModel.fromMap(doc.data()!);
    final index = products.indexWhere((p) => p.id == productId);
    if (index >= 0) {
      products[index] = updated;
    } else {
      products.add(updated);
    }
    emit(InventoryLoaded(products));
  }

  // ---------------------------------------------------------------------
  // Add/edit product form
  // ---------------------------------------------------------------------

  void clearForm() {
    editingProduct = null;
    nameCtrl.clear();
    priceCtrl.clear();
    lowStockCtrl.text = '1';
    isActive = true;
    isFeatured = false;
    for (final row in colorRows) {
      row.dispose();
    }
    colorRows
      ..clear()
      ..add(ColorFormRow());
    pendingColorImages.clear();
    emit(InventoryFormChanged());
  }

  void fillFormForEdit(ProductModel product) {
    editingProduct = product;
    nameCtrl.text = product.name;
    priceCtrl.text = product.price.toString();
    lowStockCtrl.text = product.lowStockThreshold.toString();
    isActive = product.isActive;
    isFeatured = product.isFeatured;

    for (final row in colorRows) {
      row.dispose();
    }
    colorRows.clear();
    pendingColorImages.clear();

    if (product.colors.isEmpty) {
      colorRows.add(ColorFormRow());
    } else {
      for (final color in product.colors) {
        final row = ColorFormRow(color: color, existingImageUrl: product.imageFor(color));
        final sizes = product.stock[color] ?? {};
        row.sizes.clear();
        if (sizes.isEmpty) {
          row.sizes.add(SizeQtyRow());
        } else {
          sizes.forEach((size, qty) {
            row.sizes.add(SizeQtyRow(size: size, qty: qty.toString()));
          });
        }
        colorRows.add(row);
      }
    }
    emit(InventoryFormChanged());
  }

  void addColorRow() {
    colorRows.add(ColorFormRow());
    emit(InventoryAddRow());
  }

  void removeColorRow(int index) {
    if (index < 0 || index >= colorRows.length || colorRows.length <= 1) return;
    colorRows[index].dispose();
    colorRows.removeAt(index);
    emit(InventoryAddRow());
  }

  void addSizeRow(int colorIndex) {
    if (colorIndex < 0 || colorIndex >= colorRows.length) return;
    colorRows[colorIndex].sizes.add(SizeQtyRow());
    emit(InventoryAddRow());
  }

  void removeSizeRow(int colorIndex, int sizeIndex) {
    if (colorIndex < 0 || colorIndex >= colorRows.length) return;
    final sizes = colorRows[colorIndex].sizes;
    if (sizeIndex < 0 || sizeIndex >= sizes.length || sizes.length <= 1) return;
    sizes[sizeIndex].dispose();
    sizes.removeAt(sizeIndex);
    emit(InventoryAddRow());
  }

  void toggleActive(bool value) {
    isActive = value;
    emit(InventoryFormChanged());
  }

  void toggleFeatured(bool value) {
    isFeatured = value;
    emit(InventoryFormChanged());
  }

  void pickColorImage(String color, XFile file) {
    pendingColorImages[color] = file;
    emit(InventoryFormChanged());
  }

  Future<String> uploadColorImage({
    required String productId,
    required String color,
    required XFile imageFile,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final ref = FirebaseStorage.instance.ref('products/$productId/$color.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<Map<String, String>> _uploadPendingImages(
    String productId,
    Map<String, String> existingUrls,
  ) async {
    final Map<String, String> result = Map.from(existingUrls);
    for (final entry in pendingColorImages.entries) {
      if (entry.value == null) continue;
      result[entry.key] = await uploadColorImage(
        productId: productId,
        color: entry.key,
        imageFile: entry.value!,
      );
    }
    pendingColorImages.clear();
    return result;
  }

  ProductModel _buildProductFromInputs(String id) {
    final colors = <String>[];
    final stock = <String, Map<String, int>>{};
    final imageUrls = <String, String>{};

    for (final row in colorRows) {
      final color = row.colorCtrl.text.trim();
      if (color.isEmpty) continue;
      colors.add(color);
      if (row.existingImageUrl != null) imageUrls[color] = row.existingImageUrl!;

      final sizeMap = <String, int>{};
      for (final sizeRow in row.sizes) {
        final size = sizeRow.sizeCtrl.text.trim();
        if (size.isEmpty) continue;
        sizeMap[size] = int.tryParse(sizeRow.qtyCtrl.text.trim()) ?? 0;
      }
      stock[color] = sizeMap;
    }

    final now = DateTime.now();
    return ProductModel(
      id: id,
      name: nameCtrl.text.trim(),
      price: double.tryParse(priceCtrl.text.trim()) ?? 0,
      colors: colors,
      imageUrls: imageUrls,
      stock: stock,
      isActive: isActive,
      isFeatured: isFeatured,
      lowStockThreshold: int.tryParse(lowStockCtrl.text.trim()) ?? 1,
      createdAt: editingProduct?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> saveProduct() async {
    if (nameCtrl.text.trim().isEmpty) {
      emit(InventoryError('اسم المنتج مطلوب.'));
      return;
    }
    emit(InventoryLoading());
    try {
      final id = editingProduct?.id ?? _db.collection('products').doc().id;
      var product = _buildProductFromInputs(id);
      final uploadedUrls = await _uploadPendingImages(id, product.imageUrls);
      product = product.copyWith(imageUrls: uploadedUrls);

      await _db.collection('products').doc(id).set(product.toMap());

      final index = products.indexWhere((p) => p.id == id);
      if (index >= 0) {
        products[index] = product;
      } else {
        products.add(product);
      }
      clearForm();
      emit(InventorySuccess('تم حفظ المنتج بنجاح.'));
    } catch (e) {
      emit(InventoryError(e.toString()));
    }
  }

  Future<void> deleteProduct(String productId) async {
    emit(InventoryLoading());
    try {
      await _db.collection('products').doc(productId).delete();
      products.removeWhere((p) => p.id == productId);
      emit(InventorySuccess('تم حذف المنتج.'));
    } catch (e) {
      emit(InventoryError(e.toString()));
    }
  }

  // ---------------------------------------------------------------------
  // Restock-only flow (does not touch any other field on the product)
  // ---------------------------------------------------------------------

  void loadProductForRestock(ProductModel product) {
    restockProduct = product;
    for (final r in restockRows) {
      r.dispose();
    }
    restockRows
      ..clear()
      ..add(RestockRowControllers());
    emit(InventoryFormChanged());
  }

  void addRestockRow() {
    restockRows.add(RestockRowControllers());
    emit(InventoryAddRow());
  }

  void removeRestockRow(int index) {
    if (index >= 0 && index < restockRows.length && restockRows.length > 1) {
      restockRows[index].dispose();
      restockRows.removeAt(index);
      emit(InventoryAddRow());
    }
  }

  Future<void> addStockQuantities({
    required String productId,
    required Map<String, Map<String, int>> additions, // color -> size -> qtyToAdd
  }) async {
    try {
      emit(InventoryLoading());

      final Map<String, dynamic> updates = {};
      additions.forEach((color, sizes) {
        sizes.forEach((size, qty) {
          if (qty == 0) return;
          updates['stock.$color.$size'] = FieldValue.increment(qty);
        });
      });

      if (updates.isEmpty) {
        emit(InventoryError('لم تُدخل أي كمية لإضافتها.'));
        return;
      }

      updates['updatedAt'] = DateTime.now().toIso8601String();
      await _db.collection('products').doc(productId).update(updates);
      await reloadSingle(productId);

      for (final r in restockRows) {
        r.dispose();
      }
      restockRows
        ..clear()
        ..add(RestockRowControllers());
      restockProduct = null;

      emit(InventorySuccess('تمت إضافة الكمية بنجاح.'));
    } catch (e) {
      emit(InventoryError(e.toString()));
    }
  }

  Future<void> submitRestock() async {
    if (restockProduct == null) {
      emit(InventoryError('اختر منتجًا أولًا.'));
      return;
    }

    final Map<String, Map<String, int>> additions = {};
    for (final r in restockRows) {
      final color = r.colorCtrl.text.trim();
      final size = r.sizeCtrl.text.trim();
      final qty = int.tryParse(r.qtyCtrl.text.trim()) ?? 0;
      if (color.isEmpty || size.isEmpty || qty <= 0) continue;
      additions.putIfAbsent(color, () => {});
      additions[color]![size] = (additions[color]![size] ?? 0) + qty;
    }

    await addStockQuantities(productId: restockProduct!.id, additions: additions);
  }

  // ---------------------------------------------------------------------
  // Excel import/export
  // ---------------------------------------------------------------------

  String _cellText(xls.Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    return v.toString().trim();
  }

  /// Columns expected, in order: product name | color | size | quantity | low-stock threshold (optional)
  Future<void> importProductsFromExcel() async {
    try {
      emit(InventoryLoading());

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) {
        emit(InventoryError('لم يتم اختيار ملف.'));
        return;
      }

      final excelFile = xls.Excel.decodeBytes(result.files.single.bytes!);
      final sheet = excelFile.tables[excelFile.tables.keys.first]!;
      final Map<String, _ImportedProduct> parsed = {};

      for (var i = 1; i < sheet.maxRows; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;
        final name = row.isNotEmpty ? _cellText(row[0]) : '';
        final color = row.length > 1 ? _cellText(row[1]) : '';
        final size = row.length > 2 ? _cellText(row[2]) : '';
        final qtyText = row.length > 3 ? _cellText(row[3]) : '';
        final thresholdText = row.length > 4 ? _cellText(row[4]) : '';
        if (name.isEmpty || color.isEmpty || size.isEmpty) continue;

        final qty = int.tryParse(qtyText) ?? 0;
        final entry = parsed.putIfAbsent(name, () => _ImportedProduct(name));
        entry.colors.add(color);
        entry.stock.putIfAbsent(color, () => {});
        entry.stock[color]![size] = qty;

        final threshold = int.tryParse(thresholdText);
        if (threshold != null) entry.threshold = threshold;
      }

      if (parsed.isEmpty) {
        emit(InventoryError('لم يتم العثور على بيانات صالحة في الملف.'));
        return;
      }

      final nowIso = DateTime.now().toIso8601String();
      var successCount = 0;

      for (final entry in parsed.values) {
        final docRef = _db.collection('products').doc(entry.name);
        final snap = await docRef.get();
        final exists = snap.exists;

        final existingColors = exists
            ? List<String>.from((snap.data()?['colors'] as List?) ?? [])
            : <String>[];
        final mergedColors = {...existingColors, ...entry.colors}.toList();

        final Map<String, dynamic> updateData = {
          'id': entry.name,
          'name': entry.name,
          'colors': mergedColors,
          'stock': entry.stock,
          'updatedAt': nowIso,
          'isActive': true,
        };

        if (!exists) {
          updateData['createdAt'] = nowIso;
          updateData['lowStockThreshold'] = entry.threshold ?? 1;
        } else if (entry.threshold != null) {
          updateData['lowStockThreshold'] = entry.threshold;
        }

        await docRef.set(updateData, SetOptions(merge: true));
        successCount++;
      }

      await fetchProducts(refresh: true);
      emit(InventorySuccess('تم استيراد/تعديل $successCount منتج بنجاح.'));
    } catch (e) {
      emit(InventoryError('فشل الاستيراد: $e'));
    }
  }

  Future<void> exportProductsToExcel() async {
    try {
      emit(InventoryLoading());

      final snap = await _db.collection('products').get();
      final workbook = xls.Excel.createExcel();
      final sheet = workbook['المنتجات'];
      workbook.delete('Sheet1');

      sheet.appendRow([
        xls.TextCellValue('اسم المنتج'),
        xls.TextCellValue('اللون'),
        xls.TextCellValue('المقاس'),
        xls.TextCellValue('الكمية'),
        xls.TextCellValue('حد التنبيه'),
      ]);

      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['name'] as String? ?? doc.id;
        final threshold = data['lowStockThreshold']?.toString() ?? '';
        final stock = Map<String, dynamic>.from(data['stock'] as Map? ?? {});

        stock.forEach((color, sizes) {
          final sizeMap = Map<String, dynamic>.from(sizes as Map);
          sizeMap.forEach((size, qty) {
            sheet.appendRow([
              xls.TextCellValue(name),
              xls.TextCellValue(color),
              xls.TextCellValue(size),
              xls.IntCellValue((qty as num).toInt()),
              xls.TextCellValue(threshold),
            ]);
          });
        });
      }

      final bytes = workbook.save();
      if (bytes == null) throw Exception('فشل إنشاء الملف.');

      final fileName = 'products_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ ملف المنتجات',
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (savedPath == null) {
        emit(InventoryFormChanged());
        return;
      }
      emit(InventorySuccess('تم حفظ الملف في: $savedPath'));
    } catch (e) {
      emit(InventoryError('فشل التصدير: $e'));
    }
  }

  @override
  Future<void> close() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    lowStockCtrl.dispose();
    for (final row in colorRows) {
      row.dispose();
    }
    for (final r in restockRows) {
      r.dispose();
    }
    return super.close();
  }
}

class _ImportedProduct {
  final String name;
  final Set<String> colors = {};
  final Map<String, Map<String, int>> stock = {};
  int? threshold;
  _ImportedProduct(this.name);
}
