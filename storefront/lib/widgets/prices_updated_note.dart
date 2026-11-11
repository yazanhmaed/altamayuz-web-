import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Gentle one-line note shown in the cart/checkout after a promotion started
/// or ended and moved the price of something already in the cart.
class PricesUpdatedNote extends StatelessWidget {
  final VoidCallback onDismiss;
  final EdgeInsetsGeometry margin;
  const PricesUpdatedNote({
    super.key,
    required this.onDismiss,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'تم تحديث الأسعار',
              style: TextStyle(fontSize: 13, color: AppColors.accent),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: 'إغلاق',
            icon: const Icon(Icons.close_rounded),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
