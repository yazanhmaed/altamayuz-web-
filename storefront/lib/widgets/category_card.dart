import 'package:flutter/material.dart';
import '../screens/category_products_page.dart';
import 'ui_helpers.dart';

/// Image-cover category tile: the category's first product photo under a dark
/// gradient, with the category name and product count. Tapping opens the
/// matching [CategoryProductsPage]. Used on the home screen and the full
/// categories page.
class CategoryCard extends StatelessWidget {
  final String name;
  final int count;
  final String coverImage;

  const CategoryCard({
    super.key,
    required this.name,
    required this.count,
    required this.coverImage,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          StoreImage(url: coverImage),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.45, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count منتج',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          // Tap feedback layered on top of the opaque image/gradient so the
          // ripple is actually visible (it would be hidden behind them if the
          // InkWell wrapped the card from outside).
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryProductsPage(category: name),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
