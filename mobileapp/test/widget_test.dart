// Smoke test: the app boots and renders its root MaterialApp without throwing.
//
// The camera list is a global that main() populates from availableCameras();
// it stays empty under the test binding, which the UI handles gracefully.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:landr_mobile/main.dart';

void main() {
  testWidgets('LandrApp builds its root MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(const LandrApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
