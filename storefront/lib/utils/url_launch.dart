import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in an external application / new browser tab. Swallows any
/// failure (bad URL, no handler, launch rejected) so a dead link can never
/// crash the app — the worst case is nothing happening.
Future<void> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    debugPrint('openExternalUrl failed for $url: $e');
  }
}
