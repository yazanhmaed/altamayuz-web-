import 'package:flutter/material.dart';

import '../config/store_info.dart';
import '../screens/about_page.dart';
import '../screens/categories_page.dart';
import '../screens/category_products_page.dart';
import '../screens/contact_page.dart';
import '../screens/shipping_policy_page.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'social_icons_row.dart';

/// Home-screen footer: section links (incl. the shipping policy page), social
/// icons and copyright. Rendered once as the final sliver of the home `CustomScrollView`
/// — not reused on other screens (they have back navigation already).
class StoreFooter extends StatelessWidget {
  const StoreFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ResponsiveCenter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  // _FooterLink(
                  //   label: 'الرئيسية',
                  //   // Footer only exists on the home screen; if somehow reached
                  //   // deeper in the stack this returns to the first route,
                  //   // otherwise it's a harmless no-op.
                  //   onTap: () =>
                  //       Navigator.of(context).popUntil((r) => r.isFirst),
                  // ),
                  _FooterLink(
                    label: 'الأصناف',
                    // Opens the full category list; each row drills into the
                    // matching CategoryProductsPage. Same category set the home
                    // chip row shows.
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CategoriesPage(),
                      ),
                    ),
                  ),
                  _FooterLink(
                    label: 'الخصومات',
                    // Discounts have landed (PublicProductModel.salePrice), so
                    // this goes straight to the on-sale grid.
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CategoryProductsPage(
                          onlyOnSale: true,
                          titleOverride: 'عروض خاصة',
                        ),
                      ),
                    ),
                  ),
                  _FooterLink(
                    label: 'من نحن',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutPage()),
                    ),
                  ),
                  _FooterLink(
                    label: 'تواصل معنا',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ContactPage()),
                    ),
                  ),
                  _FooterLink(
                    label: 'سياسة الشحن والتوصيل',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ShippingPolicyPage(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const SocialIconsRow(),
              const SizedBox(height: 20),
              Text(
                '© 2026 $storeName',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        disabledForegroundColor: AppColors.textPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
