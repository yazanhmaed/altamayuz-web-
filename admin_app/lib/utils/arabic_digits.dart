import 'package:flutter/services.dart';

const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';
const _extendedArabicIndic = '۰۱۲۳۴۵۶۷۸۹';

/// Converts Arabic-Indic and Extended Arabic-Indic digits to plain Western
/// digits. Safe to call on any string; non-digit characters pass through.
String normalizeDigits(String input) {
  final buffer = StringBuffer();
  for (final ch in input.split('')) {
    final i1 = _arabicIndic.indexOf(ch);
    if (i1 != -1) {
      buffer.write(i1.toString());
      continue;
    }
    final i2 = _extendedArabicIndic.indexOf(ch);
    if (i2 != -1) {
      buffer.write(i2.toString());
      continue;
    }
    buffer.write(ch);
  }
  return buffer.toString();
}

/// Live input formatter — converts Arabic-Indic digits to Western digits as
/// the user types, so numeric fields always display/store Western digits.
class ArabicDigitsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final converted = normalizeDigits(newValue.text);
    if (converted == newValue.text) return newValue;
    return newValue.copyWith(
      text: converted,
      selection: TextSelection.collapsed(offset: converted.length),
    );
  }
}
