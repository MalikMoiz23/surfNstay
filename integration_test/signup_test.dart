import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surfNstay/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Signup Workflow Test', () {
    testWidgets('Successful Traveller Signup', (WidgetTester tester) async {
      // 1. Launch the app
      app.main();
      
      // Wait for the LaunchScreen splash timer (5 seconds) to finish
      await tester.pumpAndSettle(const Duration(seconds: 6));

      // 2. Navigate to Signup from Login Screen
      final signupLink = find.text('Sign Up');
      expect(signupLink, findsOneWidget);
      await tester.tap(signupLink);
      await tester.pumpAndSettle();

      // 3. Choose 'Sign up as Traveller'
      final travellerOption = find.text('Sign up as Traveller');
      expect(travellerOption, findsOneWidget);
      await tester.tap(travellerOption);
      await tester.pumpAndSettle();

      // 4. Fill Signup Form
      // Using a unique timestamp to avoid 'Email already exists' error
      final uniqueId = DateTime.now().millisecondsSinceEpoch;
      final testEmail = 'tester_$uniqueId@gmail.com';

      await tester.enterText(find.widgetWithText(TextField, 'Full Name'), 'Automated Test User');
      await tester.enterText(find.widgetWithText(TextField, 'Address'), '123 Testing Lane');
      await tester.enterText(find.widgetWithText(TextField, 'Phone Number'), '03001234567');
      await tester.enterText(find.widgetWithText(TextField, 'Email'), testEmail);
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'password123');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm Password'), 'password123');

      // 5. Submit the form
      final createAccountBtn = find.text('Create Account');
      expect(createAccountBtn, findsOneWidget);
      await tester.tap(createAccountBtn);

      // 6. Verification
      // Wait for the loading to finish and the dialog to appear
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      
      // Look for the success dialog text
      // We use a try-catch or a Finder that allows us to see what happened
      final successText = find.text('Account created successfully');
      
      if (successText.evaluate().isNotEmpty) {
        print('--- TEST PASSED: Success Dialog Found ---');
      } else {
        // Fallback: If the dialog already closed, we should be back at Login
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.text('Welcome to SurfNStay'), findsOneWidget);
        print('--- TEST PASSED: Signup complete (Back at Login) ---');
      }
      
      // CRITICAL: Wait for the 900ms delay and navigation in TravellerSignupScreen to finish
      // otherwise the test fails with "failed after it had already completed"
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      print('--- TEST COMPLETED: Traveller Signup Successful with $testEmail ---');
    });

    testWidgets('Duplicate Email Signup Detection', (WidgetTester tester) async {
      // 1. Launch the app
      app.main();
      
      // Wait for the LaunchScreen splash timer
      await tester.pumpAndSettle(const Duration(seconds: 6));

      // 2. Navigate to Signup
      final signupBtn = find.text('Sign Up');
      await tester.tap(signupBtn);
      await tester.pumpAndSettle();

      // 3. Choose Traveller
      await tester.tap(find.text('Sign up as Traveller'));
      await tester.pumpAndSettle();

      // 4. Fill Signup Form with EXISTING EMAIL
      await tester.enterText(find.widgetWithText(TextField, 'Full Name'), 'Duplicate Tester');
      await tester.enterText(find.widgetWithText(TextField, 'Address'), '123 Testing Lane');
      await tester.enterText(find.widgetWithText(TextField, 'Phone Number'), '03000000000');
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'moiz3@gmail.com');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'password123');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm Password'), 'password123');

      // 5. Submit the form
      await tester.tap(find.text('Create Account'));
      
      // 6. Verification: Check for Error message
      // We expect an error dialog because the email exists
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      
      // Look for any text containing "Error" or the specific Supabase message
      final errorOccurred = find.textContaining('Error').evaluate().isNotEmpty || 
                           find.textContaining('already registered').evaluate().isNotEmpty;
      
      expect(errorOccurred, isTrue, reason: 'System should have shown an error for duplicate email');
      
      print('--- TEST PASSED: Duplicate Email Signup correctly blocked for moiz3@gmail.com ---');
    });
  });
}
