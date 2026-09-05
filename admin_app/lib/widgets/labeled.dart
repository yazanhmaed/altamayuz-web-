import 'package:flutter/material.dart';

class Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const Labeled({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
