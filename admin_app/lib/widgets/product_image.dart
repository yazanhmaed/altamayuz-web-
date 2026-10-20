import 'package:flutter/material.dart';

/// Network product image decoded at a limited width, with a neutral fill
/// while loading and a placeholder icon when there's no URL or it fails.
class ProductImage extends StatelessWidget {
  final String? url;
  final int cacheWidth;
  final double placeholderIconSize;

  const ProductImage({
    super.key,
    required this.url,
    this.cacheWidth = 400,
    this.placeholderIconSize = 36,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: placeholderIconSize,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;

    return Image.network(
      url!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : ColoredBox(color: scheme.surfaceContainerHighest),
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
