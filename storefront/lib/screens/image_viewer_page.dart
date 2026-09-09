import 'package:flutter/material.dart';

import '../widgets/ui_helpers.dart';

/// Full-screen "lightbox" viewer for a single product photo. Pinch-to-zoom and
/// drag-to-pan via [InteractiveViewer], double-tap to toggle fit/2.5x, and an
/// explicit close button (tapping the image never dismisses — that would clash
/// with double-tap-to-zoom). Opened as a non-opaque fade route so the product
/// detail page underneath stays alive with its selection state.
class ImageViewerPage extends StatelessWidget {
  final String imageUrl;
  const ImageViewerPage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fills the screen (not Center'd) so InteractiveViewer gets bounded
          // constraints and the pan/zoom viewport is the whole screen; the
          // photo itself is still centred by StoreImage's BoxFit.contain.
          Positioned.fill(child: _DoubleTapZoomImage(imageUrl: imageUrl)),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              tooltip: 'إغلاق',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoubleTapZoomImage extends StatefulWidget {
  final String imageUrl;
  const _DoubleTapZoomImage({required this.imageUrl});

  @override
  State<_DoubleTapZoomImage> createState() => _DoubleTapZoomImageState();
}

class _DoubleTapZoomImageState extends State<_DoubleTapZoomImage>
    with SingleTickerProviderStateMixin {
  static const double _doubleTapScale = 2.5;

  final TransformationController _controller = TransformationController();
  late final AnimationController _animController;

  Animation<Matrix4>? _matrixAnimation;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    // Created here (not as a `late` initializer) so the ticker's context
    // lookup happens while the element is mounted — a lazy init that first
    // runs inside dispose() throws "deactivated widget's ancestor".
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final anim = _matrixAnimation;
        if (anim != null) _controller.value = anim.value;
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _matrixAnimation = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward(from: 0);
  }

  void _handleDoubleTap() {
    final zoomedIn = _controller.value.getMaxScaleOnAxis() > 1.01;
    if (zoomedIn) {
      _animateTo(Matrix4.identity());
      return;
    }
    // Scale by _doubleTapScale, keeping the double-tapped point fixed on
    // screen. Column-major: [scale on x, scale on y, ..., translate x/y].
    const s = _doubleTapScale;
    final p = _doubleTapDetails?.localPosition ?? Offset.zero;
    _animateTo(Matrix4(
      s, 0, 0, 0, //
      0, s, 0, 0, //
      0, 0, 1, 0, //
      -p.dx * (s - 1), -p.dy * (s - 1), 0, 1, //
    ));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1.0,
        maxScale: 4.0,
        // StoreImage (not a raw Image.network) so the app-wide loading
        // spinner / error placeholder / CORS-safe decode path applies here.
        child: StoreImage(url: widget.imageUrl, fit: BoxFit.contain),
      ),
    );
  }
}
