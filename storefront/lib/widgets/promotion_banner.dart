import 'package:flutter/material.dart';

import '../data/promotions_repository.dart';
import '../theme/app_theme.dart';

/// Slim strip under the top promo bar announcing a product-group promotion.
/// Shown only when exactly one promotion is running (several at once would
/// need a different design); uses its `bannerText` when set, else its name,
/// plus the end date. Renders nothing otherwise — no gap.
class PromotionBanner extends StatelessWidget {
  const PromotionBanner({super.key});

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _endLabel(DateTime end) {
    final local = end.toLocal();
    return 'ينتهي ${local.day}/${local.month} الساعة ${_two(local.hour)}:${_two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: promotionsRepository,
      builder: (context, _) {
        final running = promotionsRepository.running;
        if (running.length != 1) return const SizedBox.shrink();
        final promo = running.single;
        final title = promo.bannerText ?? promo.name;
        return Container(
          width: double.infinity,
          color: AppColors.danger.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.local_fire_department_outlined,
                  color: AppColors.danger, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ' · ${_endLabel(promo.endAt)}'),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
