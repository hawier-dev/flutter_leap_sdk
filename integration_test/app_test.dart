import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_leap_sdk_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Flutter LEAP SDK Integration Tests', () {
    testWidgets('App loads and shows initial state', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Verify initial UI elements
      expect(find.text('Flutter LEAP SDK Demo'), findsOneWidget);
      expect(find.text('Download Model'), findsOneWidget);
      expect(find.text('Load Model'), findsOneWidget);
      expect(find.text('No model loaded'), findsOneWidget);
    });

    testWidgets('Download button is clickable', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Find and tap download button
      final downloadButton = find.text('Download Model');
      expect(downloadButton, findsOneWidget);
      
      await tester.tap(downloadButton);
      await tester.pump();
      
      // Should show downloading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Text input works correctly', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Find text field and enter text
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      
      await tester.enterText(textField, 'Hello AI!');
      await tester.pump();
      
      // Verify text was entered
      expect(find.text('Hello AI!'), findsOneWidget);
    });
  });
}