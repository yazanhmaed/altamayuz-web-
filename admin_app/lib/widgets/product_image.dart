import 'dart:async';

import 'package:flutter/material.dart';

/// Network product image decoded at a limited width, with a spinner while
/// loading and a placeholder icon when there's no URL or it fails.
///
/// A failed load is evicted from the image cache and retried a couple of
/// times. On web, Flutter's NetworkImage keeps failures cached for the whole
/// session, so without this a single early failure (e.g. right after a new
/// image is uploaded) would show the placeholder until the page is reloaded.
class ProductImage extends StatefulWidget {
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
  State<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<ProductImage> {
  static const _maxRetries = 2;
  int _attempt = 0;
  Timer? _retryTimer;

  ImageProvider _provider(String url) =>
      ResizeImage(NetworkImage(url), width: widget.cacheWidth);

  @override
  void didUpdateWidget(ProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cacheWidth != widget.cacheWidth) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _attempt = 0;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _scheduleRetry(String url) {
    if (_retryTimer != null || _attempt >= _maxRetries) return;
    _retryTimer = Timer(Duration(seconds: 1 << _attempt), () {
      _retryTimer = null;
      if (!mounted || widget.url != url) return;
      _provider(url).evict();
      setState(() => _attempt++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: widget.placeholderIconSize,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
    final url = widget.url;
    if (url == null || url.isEmpty) return placeholder;

    final loading = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );

    return Image(
      // A new URL (or a retry) gets a fresh Image state instead of reusing
      // the previous one's error.
      key: ValueKey('$url#$_attempt'),
      image: _provider(url),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) => progress == null ? child : loading,
      errorBuilder: (_, __, ___) {
        if (_attempt < _maxRetries) {
          _scheduleRetry(url);
          return loading;
        }
        return placeholder;
      },
    );
  }
}
