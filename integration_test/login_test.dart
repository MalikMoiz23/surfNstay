import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surfNstay/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Login Workflow Test', () {
    testWidgets('Successful Login', (WidgetTester tester) async {
      // 1. Launch the app
      app.main();
      
      // Wait for the LaunchScreen splash timer (5 seconds) to finish
      await tester.pumpAndSettle(const Duration(seconds: 6));

      // 2. Locate components on Login Screen
      final emailField = find.widgetWithText(TextField, 'Email');
      final passwordField = find.widgetWithText(TextField, 'Password');
      final loginBtn = find.text('Login');

      // 3. Enter Correct Credentials
      await tester.enterText(emailField, 'moiz3@gmail.com');
      await tester.enterText(passwordField, '1234567890');
      await tester.tap(loginBtn);

      // 4. Wait for authentication and navigation
      await tester.pump(const Duration(seconds: 1)); // Small delay for async
      await tester.pumpAndSettle();

      // 5. Verify Successful Login
      // Dashboard usually contains specific text like "Explore" or a user icon
      // We'll check for the dashboard structure
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      
      print('--- TEST PASSED: Successful Login with moiz3@gmail.com ---');
    });

    testWidgets('Invalid Login Handling', (WidgetTester tester) async {
      // 1. Launch the app
      app.main();
      
      // Wait for the LaunchScreen splash timer
      await tester.pumpAndSettle(const Duration(seconds: 6));

      // 2. Enter INCORRECT Credentials
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'moiz3@gmail.com');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrongpassword_xyz');
      await tester.tap(find.text('Login'));

      // 3. Wait for error handling
      await tester.pumpAndSettle();

      // 4. Verify Error Message
      // The SnackBar should contain "Login failed"
      final errorMsg = find.textContaining('Login failed');
      expect(errorMsg, findsOneWidget, reason: 'Expected to see a SnackBar with "Login failed"');
      
      print('--- TEST PASSED: Invalid Login correctly blocked with error message ---');
    });
  });
}
