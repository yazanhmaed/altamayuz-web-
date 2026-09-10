import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../config/store_info.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/url_launch.dart';
import '../widgets/social_icons_row.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تواصل معنا'),
        centerTitle: true,
      ),
      body: ResponsiveCenter(
        maxWidth: 900,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              // Header Intro
              Icon(
                Icons.support_agent_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'يسعدنا تواصلك معنا',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'نحن هنا لمساعدتك والإجابة على استفساراتك في أي وقت.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),

              // Contact Cards (Row for Desktop, Column for Mobile)
              Flex(
                direction: isDesktop ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: isDesktop
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.stretch,
                children: [
                  // WhatsApp Card
                  Expanded(
                    flex: isDesktop ? 1 : 0,
                    child: _ContactOptionCard(
                      // icon: FaIcon(FontAwesomeIcons.whatsapp),
                      faIcon: FontAwesomeIcons.whatsapp,
                      iconColor: const Color(0xFF25D366),
                      title: 'واتساب',
                      subtitle: 'دردشة مباشرة مع فريق الدعم',
                      buttonLabel: 'تواصل عبر واتساب',
                      buttonColor: const Color(0xFF25D366),
                      onPressed: () =>
                          openExternalUrl('https://wa.me/$whatsappPhone'),
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? 20 : 0,
                    height: isDesktop ? 0 : 16,
                  ),
                  // Phone Card
                  Expanded(
                    flex: isDesktop ? 1 : 0,
                    child: _ContactOptionCard(
                      icon: Icons.phone_in_talk_rounded,
                      iconColor: theme.colorScheme.primary,
                      title: 'الاتصال المباشر',
                      subtitle: 'متاحين للرد على مكالماتك',
                      buttonLabel: contactPhone,
                      buttonColor: theme.colorScheme.primary,
                      onPressed: () => openExternalUrl('tel:$contactPhone'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 48),

              // Social Media Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      // ignore: deprecated_member_use
                      .withOpacity(0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    // ignore: deprecated_member_use
                    color: AppColors.border.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'تابعنا على مواقع التواصل الاجتماعي',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const SocialIconsRow(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactOptionCard extends StatelessWidget {
  final IconData? icon;
  final FaIconData? faIcon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final Color buttonColor;
  final VoidCallback onPressed;

  const _ContactOptionCard({
    this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.buttonColor,
    required this.onPressed,
    this.faIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          // ignore: deprecated_member_use
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                // ignore: deprecated_member_use
                color: iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: icon == null
                  ? FaIcon(
                      faIcon,
                      color: iconColor,
                      size: 32,
                    )
                  : Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: onPressed,
                icon: icon == null
                    ? FaIcon(
                        faIcon,
                        size: 20,
                      )
                    : Icon(icon, size: 20),
                label: Text(
                  buttonLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
