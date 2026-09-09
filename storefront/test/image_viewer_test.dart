import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altamayuz_storefront/screens/image_viewer_page.dart';

void main() {
  testWidgets('ImageViewerPage: bounded InteractiveViewer + wired close button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ImageViewerPage(imageUrl: '')),
    );

    final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(iv.minScale, 1.0);
    expect(iv.maxScale, 4.0);

    final closeBtn = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(IconButton),
      ),
    );
    expect(closeBtn.onPressed, isNotNull);

    // A single tap on the image must NOT dismiss the viewer (would clash with
    // double-tap-to-zoom).
    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400)); // clear dbl-tap timer
    expect(find.byType(ImageViewerPage), findsOneWidget);
  });

  testWidgets('ImageViewerPage: double-tap toggles between fit and ~2.5x',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ImageViewerPage(imageUrl: '')),
    );

    final ivFinder = find.byType(InteractiveViewer);
    double scale() => tester
        .widget<InteractiveViewer>(ivFinder)
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    expect(scale(), closeTo(1.0, 0.001));

    final center = tester.getCenter(ivFinder);
    Future<void> doubleTap() async {
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pump(); // let onDoubleTap fire + the animation start
      await tester.pump(const Duration(milliseconds: 300)); // finish 220ms zoom
    }

    await doubleTap();
    expect(scale(), greaterThan(2.0));
    expect(scale(), lessThan(3.0));

    await doubleTap();
    expect(scale(), closeTo(1.0, 0.001));
  });
}
