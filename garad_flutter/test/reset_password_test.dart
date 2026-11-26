import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/auth_state.dart';
import 'package:garad_ai/screens/reset_password_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// The reset link in the email opens the app's "Choose a new password" screen.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('only garad.ai reset links are taken as reset links', () {
    const code = 'abcDEF123abcDEF123abcDEF123abcDEF123abcDEF123abcd-1795700000';
    expect(passwordResetCode(Uri.parse('https://garad.ai/forgot-password/retrieve/$code')), code);
    expect(passwordResetCode(Uri.parse('https://www.garad.ai/forgot-password/retrieve/$code')), code);
    expect(passwordResetCode(Uri.parse('https://garad.ai/forgot-password')), isNull);
    expect(passwordResetCode(Uri.parse('https://garad.ai/forgot-password/retrieve/')), isNull);
    expect(passwordResetCode(Uri.parse('https://evil.example/forgot-password/retrieve/$code')), isNull);
    expect(passwordResetCode(Uri.parse('http://garad.ai/forgot-password/retrieve/$code')), isNull);
    expect(passwordResetCode(Uri.parse('garadai://voice')), isNull);
  });

  ({AuthState auth, List<Map<String, dynamic>> sent}) server({bool expired = false}) {
    final sent = <Map<String, dynamic>>[];
    final api = GaradApi(
      client: MockClient((request) async {
        http.Response json(Object data, [int status = 200]) =>
            http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json'});
        if (request.method == 'POST' && request.url.path.endsWith('/auth/reset-password')) {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (expired) {
            return json({
              'message': 'This reset link has expired or was already used. Please request a new one.',
            }, 410);
          }
          return json({
            'token': '9|new-login',
            'user': {'id': 7, 'name': 'Afrah', 'surname': '', 'email': 'afrah@example.com', 'google': false},
          });
        }
        return json({'message': 'not found'}, 404);
      }),
    );
    return (auth: AuthState(api), sent: sent);
  }

  Future<void> open(WidgetTester tester, AuthState auth) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>.value(
        value: auth,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ResetPasswordScreen(code: 'the-code')),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a new password is saved and the phone is signed in', (tester) async {
    final s = server();
    await open(tester, s.auth);
    expect(find.text('Choose a new password'), findsOneWidget);

    // Checked here first: too short, then two different passwords.
    await tester.enterText(find.byType(TextField).at(0), 'short');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 8 characters'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'brand-new-pass-1');
    await tester.enterText(find.byType(TextField).at(1), 'brand-new-pass-2');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(find.text("The two passwords don't match."), findsOneWidget);
    expect(s.sent, isEmpty);

    await tester.enterText(find.byType(TextField).at(1), 'brand-new-pass-1');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(s.sent.single['code'], 'the-code');
    expect(s.sent.single['password'], 'brand-new-pass-1');
    expect(s.auth.signedIn, isTrue);
    expect(s.auth.user!.email, 'afrah@example.com');
    expect(find.text('Choose a new password'), findsNothing, reason: 'back to the app, signed in');
    expect(find.text('Your new password is saved.'), findsOneWidget);
  });

  testWidgets('a used or old link says so and offers a new link', (tester) async {
    final s = server(expired: true);
    await open(tester, s.auth);

    await tester.enterText(find.byType(TextField).at(0), 'brand-new-pass-1');
    await tester.enterText(find.byType(TextField).at(1), 'brand-new-pass-1');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(find.textContaining('expired or was already used'), findsOneWidget);
    expect(s.auth.signedIn, isFalse);
    await tester.tap(find.text('Request a new link'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsNothing);
  });
}
