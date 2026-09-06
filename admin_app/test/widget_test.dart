// Minimal smoke test. The full app requires Firebase.initializeApp(), which
// isn't available in the plain test environment, so we just verify a trivial
// widget tree pumps without error.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp pumps', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('ok'))),
    );
    expect(find.text('ok'), findsOneWidget);
  });
}
