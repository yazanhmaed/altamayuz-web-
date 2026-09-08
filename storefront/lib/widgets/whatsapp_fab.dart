import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../config/store_info.dart';
import '../utils/url_launch.dart';

/// Floating button that opens a WhatsApp chat with the store. Home screen only
/// (same "home-only" boundary as [StoreFooter]).
///
/// Deliberately uses WhatsApp's brand green (`0xFF25D366`) rather than
/// `AppColors.accent` so it reads as "WhatsApp" at a glance — the same
/// recognizability exception [DiscountBadge] makes with `AppColors.danger`.
/// The glyph matches the one [SocialIconsRow] uses in the footer.
class WhatsAppFab extends StatelessWidget {
  const WhatsAppFab({super.key});

  static const Color _whatsAppGreen = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => openExternalUrl('https://wa.me/$whatsappPhone'),
      backgroundColor: _whatsAppGreen,
      foregroundColor: Colors.white,
      tooltip: 'تواصل معنا عبر واتساب',
      child: const FaIcon(FontAwesomeIcons.whatsapp),
    );
  }
}
