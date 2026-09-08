import 'package:flutter/material.dart';

import '../config/store_info.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/url_launch.dart';
import '../widgets/social_icons_row.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تواصل معنا')),
      body: ResponsiveCenter(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    openExternalUrl('https://wa.me/$whatsappPhone'),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('تواصل عبر واتساب'),
              ),
              const SizedBox(height: 20),
              const Text('للاتصال المباشر:'),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => openExternalUrl('tel:$contactPhone'),
                  icon: const Icon(Icons.phone_outlined),
                  label: const Text(
                    contactPhone,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Divider(color: AppColors.border),
              const SizedBox(height: 16),
              Text(
                'تابعنا على مواقع التواصل',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              const SocialIconsRow(),
            ],
          ),
        ),
      ),
    );
  }
}
