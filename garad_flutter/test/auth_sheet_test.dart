import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/auth_state.dart';
import 'package:garad_ai/auth_strings.dart';
import 'package:garad_ai/screens/auth_sheet.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Sign in / Sign up like garad.ai (email + password; full name to sign up; Forgot password? sends the
/// website's reset link), in the dark card with ✕.
void main() {
  // The saved login goes to the phone's secure storage; in tests, an in-memory stand-in.
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final s = authStrings;
  const user = {'id': 7, 'name': 'Amina', 'email': 'amina@example.com'};

  /// A pretend server: the password "right-password" signs in.
  ({AuthState auth, List<String> paths, List<Map<String, dynamic>> bodies}) server() {
    final paths = <String>[];
    final bodies = <Map<String, dynamic>>[];
    final api = GaradApi(
      client: MockClient((request) async {
        final path = request.url.path.replaceFirst(RegExp(r'^.*/api/mobile'), '');
        paths.add(path);
        final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        http.Response json(Object data, [int status = 200]) =>
            http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json'});
        switch (path) {
          case '/auth/login':
            if (body['password'] != 'right-password') {
              return json({
                'message': 'The email or password is incorrect.',
                'errors': {
                  'email': ['The email or password is incorrect.'],
                },
              }, 422);
            }
            return json({'token': '1|abc', 'user': user});
          case '/auth/register':
            return json({'token': '2|def', 'user': user}, 201);
          case '/auth/forgot-password':
            return json({'message': 'Password reset link sent successfully. Please also check your spam folder.'});
        }
        return json({'message': 'not found'}, 404);
      }),
    );
    return (auth: AuthState(api), paths: paths, bodies: bodies);
  }

  Future<void> openSheet(WidgetTester tester, AuthState auth) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>.value(
        value: auth,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(onPressed: () => showAuthSheet(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  /// The big white button (not the "Sign up / Sign in" switch link under it).
  Finder mainButton() => find.byType(FilledButton);

  testWidgets('sign in: email and password, then the card closes', (tester) async {
    final fake = server();
    await openSheet(tester, fake.auth);
    expect(find.text(s.signIn), findsWidgets);
    expect(find.text(s.forgotPassword), findsOneWidget);
    expect(find.text(s.google), findsOneWidget);
    expect(field(s.fullName), findsNothing, reason: 'sign in has no name box');
    expect(
      find.byTooltip(MaterialLocalizations.of(tester.element(find.byType(AuthSheet))).closeButtonTooltip),
      findsOneWidget,
      reason: 'the ✕ to close',
    );

    await tester.enterText(field(s.email), ' Amina@Example.com ');
    await tester.enterText(field(s.password), 'right-password');
    await tester.tap(mainButton());
    await tester.pumpAndSettle();
    expect(fake.paths, ['/auth/login']);
    expect(fake.bodies.last['email'], 'amina@example.com');
    expect(fake.auth.signedIn, isTrue);
    expect(find.byType(AuthSheet), findsNothing);
  });

  testWidgets('a wrong password shows the server\'s message and stays open', (tester) async {
    final fake = server();
    await openSheet(tester, fake.auth);
    await tester.enterText(field(s.email), 'amina@example.com');
    await tester.enterText(field(s.password), 'wrong');
    await tester.tap(mainButton());
    await tester.pumpAndSettle();
    expect(find.text('The email or password is incorrect.'), findsOneWidget);
    expect(fake.auth.signedIn, isFalse);
    expect(find.byType(AuthSheet), findsOneWidget);
  });

  testWidgets('sign up: full name, email, password (no phone, no second password)', (tester) async {
    final fake = server();
    await openSheet(tester, fake.auth);
    // "Don't have an account? Sign up" is at the bottom of the card: scroll to it first.
    final switchToSignUp = find.widgetWithText(TextButton, s.signUp);
    await tester.ensureVisible(switchToSignUp);
    await tester.pumpAndSettle();
    await tester.tap(switchToSignUp);
    await tester.pumpAndSettle();
    expect(field(s.fullName), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3), reason: 'full name, email, password only');
    expect(find.text(s.forgotPassword), findsNothing);

    await tester.enterText(field(s.fullName), 'Amina  Ali Warsame');
    await tester.enterText(field(s.email), 'amina@example.com');
    await tester.enterText(field(s.password), 'short');
    await tester.tap(mainButton());
    await tester.pumpAndSettle();
    expect(find.text(s.passwordShort), findsOneWidget, reason: 'at least 8 characters, checked before the server');
    expect(fake.paths, isEmpty);

    await tester.enterText(field(s.password), 'a-good-password');
    await tester.tap(mainButton());
    await tester.pumpAndSettle();
    expect(fake.paths, ['/auth/register']);
    expect(fake.bodies.last, containsPair('full_name', 'Amina Ali Warsame'));
    expect(fake.bodies.last.containsKey('phone'), isFalse);
    expect(fake.auth.signedIn, isTrue);
  });

  testWidgets('Forgot password? opens its own screen: email, Send link, back to Sign in', (tester) async {
    final fake = server();
    await openSheet(tester, fake.auth);

    // Straight to its own screen — no "type your email first".
    await tester.tap(find.text(s.forgotPassword));
    await tester.pumpAndSettle();
    expect(find.text(s.forgotTitle), findsOneWidget);
    expect(find.text(s.sendLink), findsOneWidget);
    expect(field(s.password), findsNothing, reason: 'only the email box');
    expect(find.byTooltip(s.back), findsOneWidget, reason: '‹ back to Sign in');
    expect(fake.paths, isEmpty);

    await tester.tap(find.text(s.sendLink));
    await tester.pumpAndSettle();
    expect(find.text(s.required), findsOneWidget, reason: 'empty email: asked here, on this screen');
    expect(fake.paths, isEmpty);

    await tester.enterText(field(s.email), 'Amina@example.com');
    await tester.tap(find.text(s.sendLink));
    await tester.pumpAndSettle();
    expect(fake.paths, ['/auth/forgot-password']);
    expect(fake.bodies.last['email'], 'amina@example.com');
    expect(find.text('Password reset link sent successfully. Please also check your spam folder.'), findsOneWidget);
    expect(find.text(s.sendAgain), findsOneWidget);

    await tester.tap(find.byTooltip(s.back));
    await tester.pumpAndSettle();
    expect(find.text(s.forgotPassword), findsOneWidget, reason: 'back on Sign in');
    expect(field(s.password), findsOneWidget);
  });

  testWidgets('the email typed on Sign in is already in the Forgot password box', (tester) async {
    final fake = server();
    await openSheet(tester, fake.auth);
    await tester.enterText(field(s.email), 'amina@example.com');
    await tester.tap(find.text(s.forgotPassword));
    await tester.pumpAndSettle();
    expect(find.text('amina@example.com'), findsOneWidget);
    await tester.tap(find.text(s.sendLink));
    await tester.pumpAndSettle();
    expect(fake.paths, ['/auth/forgot-password']);
  });
}
