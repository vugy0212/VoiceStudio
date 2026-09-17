// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicestudio_mobile/widgets/text_input_card.dart';

void main() {
  testWidgets('TextInputCard updates word and character counts dynamically', (WidgetTester tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextInputCard(
            controller: controller,
            selectedLanguage: 'Auto',
            onLanguageChanged: (_) {},
            onClear: () {},
          ),
        ),
      ),
    );

    // Initial state: 0 words • 0 chars
    expect(find.text('0 words • 0 chars'), findsOneWidget);

    // Type text into controller
    controller.text = 'Bok svijete, ovo je test';
    await tester.pump();

    // Verifies reactive counter
    expect(find.text('5 words • 24 chars'), findsOneWidget);
    expect(find.textContaining('estimated'), findsOneWidget);

    // Verify only ONE Paste button exists
    expect(find.text('Paste'), findsOneWidget);
    expect(find.byTooltip('Paste from clipboard'), findsNothing);
  });
}
