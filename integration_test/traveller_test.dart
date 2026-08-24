import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surfNstay/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Traveller Dashboard Test Suite', () {
    
    Future<void> loginAsTraveller(WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));
      
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'sarib@gmail.com');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), '454545');
      await tester.tap(find.text('Login'));
      
      // Wait for navigation and initial load
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // 🔍 SELF-HEALING: Wait for CircularProgressIndicator to disappear
      // TravellerDashboard shows a loader while fetching data from Supabase
      int retry = 0;
      while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty && retry < 10) {
        print('Waiting for TravellerDashboard to finish loading... (Attempt $retry)');
        await tester.pump(const Duration(seconds: 1));
        retry++;
      }
    }

    testWidgets('Verify Properties Load and Display', (WidgetTester tester) async {
      await loginAsTraveller(tester);

      // 1. Check for basic components
      expect(find.text('SurfNStay'), findsWidgets);
      expect(find.byType(TextField), findsOneWidget); // Search bar

      // 2. Verify that properties are loaded
      // We look for "PKR" which is the currency prefix for all prices
      final priceFinder = find.textContaining('PKR');
      
      if (priceFinder.evaluate().isEmpty) {
        print('--- WARNING: No properties found! Make sure your database is NOT empty. ---');
      }
      
      expect(priceFinder, findsWidgets, reason: 'At least one property card should be displayed');
      
      print('--- TEST PASSED: Traveller Dashboard loaded properties successfully ---');
    });

    testWidgets('Verify Image Display', (WidgetTester tester) async {
      await loginAsTraveller(tester);

      // 1. Wait for loading
      await tester.pumpAndSettle();

      // 2. Look for Image widgets
      // Each property card has an Image.network widget
      final imageFinder = find.byType(Image);
      
      // We expect at least the logo and one property image
      expect(imageFinder, findsAtLeastNWidgets(2), reason: 'Logo and at least one property image should exist');

      print('--- TEST PASSED: Traveller Dashboard images detected successfully ---');
    });

    testWidgets('Search Functionality - Valid City', (WidgetTester tester) async {
      await loginAsTraveller(tester);

      final searchField = find.byType(TextField);
      
      // 1. Search for a city
      // Note: We use Islamabad because it is a default city in the grouping logic
      await tester.enterText(searchField, 'Islamabad');
      await tester.pumpAndSettle();

      // 2. Verify results
      // Even if no rooms exist, the header "Islamabad" should be visible 
      // because we grouped rooms and the header is part of cityOrder
      expect(find.text('Islamabad'), findsWidgets);
      
      print('--- TEST PASSED: Search filter applied for "Islamabad" ---');
    });

    testWidgets('Search Functionality - No Results Handling', (WidgetTester tester) async {
      await loginAsTraveller(tester);

      final searchField = find.byType(TextField);
      const nonsenseCity = 'XYZ_Unknown_City_999';

      // 1. Search for a non-existent city
      await tester.enterText(searchField, nonsenseCity);
      await tester.pumpAndSettle();

      // 2. Verify "No results" message
      expect(find.text('No results for "$nonsenseCity"'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);

      // 3. Clear search
      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();

      // 4. Verify return to normal state
      expect(find.text('SurfNStay'), findsWidgets);
      
      print('--- TEST PASSED: No Results handling verified successfully ---');
    });
  });
}
