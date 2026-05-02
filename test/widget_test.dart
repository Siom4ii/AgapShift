import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexora/app/database/sqflite_platform.dart';
import 'package:nexora/main.dart';

void main() {
  testWidgets('Shows Getting Started on first launch', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    configureSqfliteForPlatform();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final view = tester.view;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    await tester.pumpWidget(const AgapShiftBootstrap());
    // Bootstrap async init + flutter_animate may never fully idle for pumpAndSettle.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('AgapShift'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
