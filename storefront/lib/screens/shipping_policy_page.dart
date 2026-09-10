import 'package:flutter/material.dart';
import '../config/store_info.dart';
import '../utils/responsive.dart';

/// Delivery + exchange policy, linked from the home footer. Content comes
/// straight from [deliveryPolicyText] (the single source of truth); this page
/// only splits that one sentence into a "التوصيل" and an "الاستبدال" section
/// for readability — no policy details beyond what that string states.
class ShippingPolicyPage extends StatelessWidget {
  const ShippingPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // deliveryPolicyText reads "<delivery>، و<exchange>". Split on that seam;
    // fall back to showing the whole sentence if the wording ever changes.
    final parts = deliveryPolicyText.split('، و');
    final deliveryText = parts.first.trim();
    final exchangeText =
        parts.length > 1 ? parts.sublist(1).join('، و').trim() : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سياسة الشحن والتوصيل'),
        centerTitle: true,
      ),
      body: ResponsiveCenter(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Column(
            children: [
              // Header / Hero Card
              SizedBox(
                width: double.infinity,
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      // ignore: deprecated_member_use
                      color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.local_shipping_rounded,
                            size: 48,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'الشحن والتوصيل',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          deliveryPolicyText,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.8,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              _PolicySection(
                icon: Icons.local_shipping_outlined,
                title: 'التوصيل',
                body: deliveryText,
              ),
              if (exchangeText != null) ...[
                const SizedBox(height: 16),
                _PolicySection(
                  icon: Icons.assignment_return_outlined,
                  title: 'الاستبدال',
                  body: exchangeText,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _PolicySection({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.6,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
