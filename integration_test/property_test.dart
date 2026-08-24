import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surfNstay/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Host Property Management Test', () {
    
    Future<void> loginAsHost(WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));
      
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'moiz3@gmail.com');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), '1234567890');
      await tester.tap(find.text('Login'));
      
      // Wait for navigation and initial load
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // 🔍 SELF-HEALING: Wait for CircularProgressIndicator to disappear
      // HostDashboard shows a loader while fetching data from Supabase
      int retry = 0;
      while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty && retry < 10) {
        print('Waiting for HostDashboard to finish loading... (Attempt $retry)');
        await tester.pump(const Duration(seconds: 1));
        retry++;
      }
    }

    testWidgets('Missing Fields Validation', (WidgetTester tester) async {
      await loginAsHost(tester);

      // 1. Navigate to Add Property Screen
      // Look for the "Add" button. Use textContaining to be flexible
      final addPropertyBtn = find.textContaining('Add');
      
      if (addPropertyBtn.evaluate().isEmpty) {
        print('--- ERROR: Could not find "Add" button. Current widgets: ---');
        debugDumpApp();
      }
      
      expect(addPropertyBtn, findsWidgets, reason: 'Dashboard should have an "Add Property" button');
      await tester.tap(addPropertyBtn.first);
      await tester.pumpAndSettle();

      // 2. Try to publish without filling fields
      final publishBtn = find.text('Publish Property');
      await tester.tap(publishBtn);
      await tester.pumpAndSettle();

      // 3. Verify Error Dialog
      expect(find.text('Rent and location are required'), findsOneWidget);
      
      // Close dialog
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      
      print('--- TEST PASSED: Property validation caught missing fields ---');
    });

    testWidgets('Add Property Listing Success', (WidgetTester tester) async {
      await loginAsHost(tester);

      // 1. Navigate to Add Property Screen
      final addPropertyBtn = find.textContaining('Add');
      await tester.tap(addPropertyBtn.first);
      await tester.pumpAndSettle();

      // 2. Fill in Details (No images for automation)
      await tester.enterText(find.widgetWithText(TextField, 'Per Night Rent (PKR)'), '4500');
      await tester.enterText(find.widgetWithText(TextField, 'Full Location'), 'Test Location, Islamabad');
      await tester.enterText(find.widgetWithText(TextField, 'Amenities / Facilities'), 'WiFi, AC, Breakfast');
      await tester.enterText(find.widgetWithText(TextField, 'Description'), 'A beautiful test stay created by automation.');

      // 3. Submit
      await tester.tap(find.text('Publish Property'));
      
      // Give time for Supabase network request
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // 4. Verify Success Dialog
      expect(find.text('Your property is now live!'), findsOneWidget);
      
      print('--- TEST PASSED: Property successfully added for moiz3@gmail.com ---');
    });
  });
}
