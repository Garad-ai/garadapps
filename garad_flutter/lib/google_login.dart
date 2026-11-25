import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'chat_strings.dart';

/// Google's sign-in failed in a way the user should hear about (not a closed account picker).
class GoogleLoginFailed implements Exception {
  GoogleLoginFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// "Continue with Google" on the phone, with Google's official google_sign_in package: on Android it
/// opens the phone's own Google account picker (Android Credential Manager) and gives back a
/// Google-signed ID token for our server, which checks it (MobileAuthController::google).
///
/// Needs, in the Google Cloud project of the website's Google login:
///  * the *web* OAuth client (GOOGLE_CLIENT_ID on the server; the app asks the server for it), and
///  * an *Android* OAuth client with package name `ai.garad.app` and the SHA-1 of the key the APK is
///    signed with. Without it Google refuses (often as if the user had closed the picker).
abstract final class GoogleLogin {
  /// Android only for now. iPhones also need an iOS OAuth client and its URL scheme in Info.plist.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void>? _ready;

  static Future<void> _initialize(String serverClientId) =>
      _ready ??= GoogleSignIn.instance.initialize(serverClientId: serverClientId).catchError((Object e) {
        _ready = null; // let the next tap try again
        throw e;
      });

  /// The account picker; the ID token for the chosen account, or null if the user closed the picker.
  static Future<String?> idToken(String serverClientId) async {
    try {
      await _initialize(serverClientId);
      if (!GoogleSignIn.instance.supportsAuthenticate()) throw GoogleLoginFailed(text.notAvailable);
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) throw GoogleLoginFailed(text.failed);
      return token;
    } on GoogleSignInException catch (e) {
      debugPrint('Google sign-in: ${e.code.name} ${e.description ?? ''}');
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
          // Also what Android reports when the app isn't registered with Google (package name / SHA-1).
          return null;
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw GoogleLoginFailed(text.notSetUp);
        case GoogleSignInExceptionCode.uiUnavailable:
          throw GoogleLoginFailed(text.notAvailable);
        case GoogleSignInExceptionCode.interrupted:
        case GoogleSignInExceptionCode.userMismatch:
        case GoogleSignInExceptionCode.unknownError:
          throw GoogleLoginFailed(text.failed);
      }
    }
  }

  /// Forgets the chosen Google account (after logging out), so the next sign-in asks again.
  static Future<void> signOut() async {
    if (_ready == null) return;
    try {
      await _ready;
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to forget, or Google is unreachable: logging out of Garad is what matters.
    }
  }

  static GoogleLoginText get text => chatStrings.isSomali ? _so : _en;
}

class GoogleLoginText {
  const GoogleLoginText({required this.notAvailable, required this.notSetUp, required this.failed});

  final String notAvailable;
  final String notSetUp;
  final String failed;
}

const _so = GoogleLoginText(
  notAvailable: 'Ku gelista Google hadda lama heli karo. Isticmaal iimaylkaaga.',
  notSetUp: 'Ku gelista Google weli looma diyaarin app-kan. Isticmaal iimaylkaaga.',
  failed: 'Ku gelista Google way guuldareysatay. Mar kale isku day.',
);

const _en = GoogleLoginText(
  notAvailable: 'Google sign-in is not available right now. Please use your email.',
  notSetUp: 'Google sign-in is not set up for this app yet. Please use your email.',
  failed: 'Google sign-in failed. Please try again.',
);
