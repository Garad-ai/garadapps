import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/api/models.dart';
import 'package:garad_ai/app_state.dart';
import 'package:garad_ai/auth_state.dart';
import 'package:garad_ai/google_login.dart';
import 'package:garad_ai/notifications.dart';
import 'package:garad_ai/screens/settings_pages.dart';
import 'package:garad_ai/screens/settings_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Settings → Profile, Privacy and Notifications: each row does something real.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ({AuthState auth, List<http.Request> calls}) server({bool google = false}) {
    final calls = <http.Request>[];
    var user = <String, dynamic>{
      'id': 7,
      'name': 'Afrah',
      'surname': '',
      'email': 'afrah@example.com',
      'phone': null,
      'google': google,
      'created_at': '2026-01-15T10:00:00Z',
    };
    final api = GaradApi(
      client: MockClient((request) async {
        calls.add(request);
        final path = request.url.path.replaceFirst(RegExp(r'^.*/api/mobile'), '');
        http.Response json(Object data, [int status = 200]) =>
            http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json'});
        final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
        switch ('${request.method} $path') {
          case 'PATCH /me':
            final parts = (body['full_name'] as String).split(' ');
            user = {...user, 'name': parts.first, 'surname': parts.skip(1).join(' '), 'phone': body['phone']};
            return json({'user': user});
          case 'POST /me/password':
            if (body['current_password'] != 'old-pass-1' && body['google_id_token'] != 'fresh-google-token') {
              return json({'message': 'Your current password is incorrect.'}, 422);
            }
            return json({'message': 'Password changed.'});
          case 'POST /me/delete-request':
            return json({'message': 'Your account deletion request has been successfully submitted'});
          case 'DELETE /conversations':
            return json({'message': 'Deleted.', 'deleted': 3});
          case 'GET /auth/google':
            return json({'client_id': 'test-client.apps.googleusercontent.com'});
        }
        return json({'message': 'not found'}, 404);
      }),
    );
    final auth = AuthState(api)..user = GaradUser.fromJson(user);
    api.token = 'test';
    return (auth: auth, calls: calls);
  }

  Future<void> open(WidgetTester tester, AuthState auth, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>.value(
        value: auth,
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Profile: change the name and add a phone', (tester) async {
    final fake = server();
    await open(tester, fake.auth, const ProfileScreen());
    expect(find.text('afrah@example.com'), findsNWidgets(2), reason: 'under the avatar and in the Email row');
    expect(find.text('15/1/2026'), findsOneWidget, reason: 'member since');

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Afrah Hassan');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fake.auth.user!.fullName, 'Afrah Hassan');
    expect(find.text('Afrah Hassan'), findsNWidgets(2));

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '+252 61 234 5678');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(jsonDecode(fake.calls.last.body), {'full_name': 'Afrah Hassan', 'phone': '+252 61 234 5678'});
    expect(find.text('+252 61 234 5678'), findsOneWidget);
  });

  testWidgets('Profile: a wrong current password shows the server\'s message', (tester) async {
    final fake = server();
    await open(tester, fake.auth, const ProfileScreen());
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Current password'), 'nope');
    await tester.enterText(find.widgetWithText(TextField, 'New password'), 'brand-new-pass');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Your current password is incorrect.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Current password'), 'old-pass-1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Password changed.'), findsOneWidget);
  });

  testWidgets('Profile: a Google account confirms with Google to set a password or delete the account', (
    tester,
  ) async {
    final fake = server(google: true);
    var googleAsked = 0;
    GoogleLogin.debugIdToken = (_) async {
      googleAsked++;
      return 'fresh-google-token';
    };
    addTearDown(() => GoogleLogin.debugIdToken = null);
    await open(tester, fake.auth, const ProfileScreen());

    await tester.tap(find.text('Set a password'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Current password'), findsNothing);
    await tester.enterText(find.byType(TextField), 'brand-new-pass');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(googleAsked, 1);
    expect(jsonDecode(fake.calls.last.body), {
      'google_id_token': 'fresh-google-token',
      'password': 'brand-new-pass',
      'password_confirmation': 'brand-new-pass',
    });

    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'someone@else.com');
    await tester.tap(find.text('Request deletion'));
    await tester.pumpAndSettle();
    expect(find.text('Type your email exactly to confirm.'), findsOneWidget);
    expect(googleAsked, 1, reason: 'a wrong email stops before Google');

    await tester.enterText(find.byType(TextField), 'afrah@example.com');
    await tester.tap(find.text('Request deletion'));
    await tester.pumpAndSettle();
    expect(googleAsked, 2);
    expect(jsonDecode(fake.calls.last.body), {'google_id_token': 'fresh-google-token'});
    expect(find.text('Your account deletion request has been successfully submitted'), findsOneWidget);
  });

  testWidgets('Profile: closing Google\'s account picker changes nothing', (tester) async {
    final fake = server(google: true);
    GoogleLogin.debugIdToken = (_) async => null;
    addTearDown(() => GoogleLogin.debugIdToken = null);
    await open(tester, fake.auth, const ProfileScreen());

    await tester.tap(find.text('Set a password'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'brand-new-pass');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm with Google to continue.'), findsOneWidget);
    expect(fake.calls.where((c) => c.url.path.endsWith('/me/password')), isEmpty);
  });

  testWidgets('Privacy: delete all chats asks first, then starts a new chat', (tester) async {
    final fake = server();
    var cleared = 0;
    await open(tester, fake.auth, PrivacyScreen(onChatsDeleted: () => cleared++));
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);

    await tester.tap(find.text('Delete all chats'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all chats?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(fake.calls.single.method, 'DELETE');
    expect(cleared, 1);
    expect(find.text('All chats deleted.'), findsOneWidget);
  });

  testWidgets('Sign out asks in a clean dialog: the question, a purple Sign out and Cancel', (tester) async {
    final fake = server();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthState>.value(value: fake.auth),
          ChangeNotifierProvider<AppState>(create: (_) => AppState(appVersion: '1.0.0')),
        ],
        child: MaterialApp(home: SettingsScreen(onOpenScheduled: () {})),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.info_outline), findsNothing, reason: 'the ⓘ button is gone');

    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Do you want to sign out?'), findsOneWidget);
    expect(find.textContaining('afrah@example.com'), findsNothing, reason: 'no email in the dialog');
    expect(find.widgetWithText(FilledButton, 'Sign out'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Do you want to sign out?'), findsNothing);
    expect(fake.auth.signedIn, isTrue, reason: 'Cancel keeps you signed in');
  });

  test('a notification shows the answer as one plain line', () {
    expect(GaradNotifications.plainPreview('## Hello\n\n**Bold** and `code`'), 'Hello Bold and code');
    expect(GaradNotifications.plainPreview('See [garad](https://garad.ai) ```dart\nx\n```'), 'See garad');
    expect(GaradNotifications.plainPreview('a' * 300).length, 180);
  });
}
