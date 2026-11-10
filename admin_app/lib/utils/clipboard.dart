import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copies [value] to the clipboard, gives a light haptic tick and shows a
/// short "تم نسخ [label]" SnackBar. Call it from a user gesture (tap /
/// long-press) so the browser allows the clipboard write on web.
Future<void> copyToClipboard(BuildContext context, String value, String label) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: value));
  HapticFeedback.selectionClick();
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('تم نسخ $label'),
      duration: const Duration(milliseconds: 1500),
    ));
}
