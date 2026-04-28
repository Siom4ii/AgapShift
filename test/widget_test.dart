import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexora/main.dart';

void main() {
  testWidgets('Shows Getting Started on first launch', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const AgapShiftBootstrap());
    // Allow bootstrap + entry animations to complete.
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('AgapShift'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
