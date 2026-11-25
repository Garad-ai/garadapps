import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/models.dart';
import 'package:garad_ai/screens/welcome_screen.dart';
import 'package:garad_ai/widgets/google_logo.dart';

/// The first screen's ways in, per device, and the website's sign-in picture it shows.
void main() {
  Future<void> showChoices(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: LoginChoices()))));

  testWidgets('Android: Continue with Google, and no Apple button', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await showChoices(tester);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(GoogleLogo), findsOneWidget, reason: 'Google\'s real four-colour G, not a letter');
    expect(find.text('G'), findsNothing);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('Log in or sign up'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iPhone: Google and Apple (Apple asks for Sign in with Apple next to Google)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await showChoices(tester);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  test('the sign-in picture: the video, or the slides, or the one fallback picture', () {
    final withVideo = WelcomeVisual.fromJson({
      'video': 'http://192.168.0.167/garad.ai/public/upload/images/auth/v.mp4',
      'slides': <String>[],
      'fallback': 'http://192.168.0.167/garad.ai/public/upload/images/auth/login.jpg',
      'bottom': 'http://192.168.0.167/garad.ai/public/upload/images/auth/arkaan.png',
      'review': 'GARAD AI Powered BY, ',
    });
    expect(withVideo.video, endsWith('v.mp4'));
    expect(withVideo.pictures, ['http://192.168.0.167/garad.ai/public/upload/images/auth/login.jpg'],
        reason: 'shown while the video loads');
    expect(withVideo.review, 'GARAD AI Powered BY,');

    final slides = WelcomeVisual.fromJson({'video': null, 'slides': ['a.jpg', 'b.jpg', ''], 'fallback': 'c.jpg'});
    expect(slides.pictures, ['a.jpg', 'b.jpg'], reason: 'the slides take turns; the fallback is not needed');

    final none = WelcomeVisual.fromJson({'video': null, 'slides': <String>[], 'fallback': null});
    expect(none.isEmpty, isTrue, reason: 'nothing set in the admin: the logo screen as before');
  });
}
