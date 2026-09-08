import 'package:flutter/material.dart';

import '../config/store_info.dart';
import '../theme/app_theme.dart';
import '../utils/url_launch.dart';

/// Facebook / Instagram / WhatsApp icon row, shared by [StoreFooter] and the
/// contact page. Each icon opens its URL externally via [openExternalUrl],
/// which never throws.
///
/// Instagram uses a neutral Material stand-in ([Icons.camera_alt_outlined]) —
/// there's no brand-icon package in the dependency set and adding one just for
/// three icons isn't worth it.
class SocialIconsRow extends StatelessWidget {
  final MainAxisAlignment alignment;
  const SocialIconsRow({super.key, this.alignment = MainAxisAlignment.center});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: alignment,
      children: [
        _SocialIcon(
          icon: Icons.facebook,
          label: 'فيسبوك',
          onTap: () => openExternalUrl(facebookUrl),
        ),
        const SizedBox(width: 8),
        _SocialIcon(
          icon: Icons.camera_alt_outlined,
          label: 'إنستغرام',
          onTap: () => openExternalUrl(instagramUrl),
        ),
        const SizedBox(width: 8),
        _SocialIcon(
          icon: Icons.chat_outlined,
          label: 'واتساب',
          onTap: () => openExternalUrl('https://wa.me/$whatsappPhone'),
        ),
      ],
    );
  }
}

class _SocialIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SocialIcon({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      icon: Icon(icon, color: AppColors.accent),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
