import 'package:flutter/services.dart';

/// Jordan country dialling code, shown as a fixed prefix on the phone field.
const String jordanDialCode = '+962';

/// Length of a Jordanian subscriber number once the national trunk `0` is
/// dropped (e.g. `0791234567` -> `791234567`).
const int jordanLocalNumberLength = 9;

/// Converts Arabic-Indic (٠-٩) and Extended Arabic-Indic / Persian (۰-۹)
/// digits to their ASCII `0-9` equivalents; other characters pass through.
String toAsciiDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(rune - 0x0660 + 0x30); // Arabic-Indic
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(rune - 0x06F0 + 0x30); // Persian
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Keeps the phone field to a bare 9-digit Jordanian number: converts
/// Arabic-Indic digits to ASCII, strips non-digits, drops any leading zero(s),
/// and caps the length at 9. The `+962` prefix is displayed separately and
/// never stored in the field.
class JordanPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = toAsciiDigits(newValue.text).replaceAll(RegExp(r'\D'), '');
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > jordanLocalNumberLength) {
      digits = digits.substring(0, jordanLocalNumberLength);
    }
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// Combines the field's local digits with [jordanDialCode] for submission,
/// e.g. `791234567` -> `+962791234567`.
String jordanPhoneToE164(String localDigits) =>
    '$jordanDialCode${toAsciiDigits(localDigits).trim()}';

/// Inverse of [jordanPhoneToE164] for populating the field when editing an
/// existing order: strips the `+962` (or bare `962`) prefix and any leading
/// zero, leaving the bare local digits the field expects.
String jordanPhoneToLocal(String stored) {
  var digits = toAsciiDigits(stored).replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('962')) digits = digits.substring(3);
  digits = digits.replaceFirst(RegExp(r'^0+'), '');
  if (digits.length > jordanLocalNumberLength) {
    digits = digits.substring(0, jordanLocalNumberLength);
  }
  return digits;
}
