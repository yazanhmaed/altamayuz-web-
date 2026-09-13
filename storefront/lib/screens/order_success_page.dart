import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class OrderSuccessPage extends StatelessWidget {
  const OrderSuccessPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: AppColors.accent, size: 72),
              const SizedBox(height: 16),
              Text('تم استلام طلبك!', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('راح نتواصل معك قريبًا لتأكيد الطلب وتفاصيل التوصيل.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(); // dismiss this plain-pushed confirmation screen
                  context.go('/'); // explicitly route home via go_router, regardless of current stack state
                },
                child: const Text('العودة للمتجر'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
