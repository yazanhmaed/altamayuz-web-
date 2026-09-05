import 'package:flutter/material.dart';

class Responsive {
  static const double mobileMax = 600;
  static const double tabletMax = 1024;
  static const double contentMaxWidth = 1200;

  static bool isWide(BuildContext context) => MediaQuery.of(context).size.width >= tabletMax;

  static int gridColumns(double width) {
    if (width < mobileMax) return 2;
    if (width < tabletMax) return 3;
    if (width < 1440) return 4;
    return 5;
  }
}

class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ResponsiveCenter({super.key, required this.child, this.maxWidth = Responsive.contentMaxWidth});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
