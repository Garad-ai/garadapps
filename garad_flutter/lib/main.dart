import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'api/garad_api.dart';
import 'app_state.dart';
import 'auth_state.dart';
import 'browser_color.dart';
import 'notifications.dart';
import 'screens/chat_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // The bundled Source Serif 4 font's license, on the app's licenses page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Source Serif 4',
    ], await rootBundle.loadString('assets/fonts/SourceSerif4-OFL.txt'));
  });

  // The splash screen stays up until the saved login has been read (see _AuthGate).
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  final info = await PackageInfo.fromPlatform();

  // `garadai://voice` (the "Talk to Garad" shortcut): open Chat Pro straight into Voice.
  final links = kIsWeb ? null : AppLinks();
  final initialLink = await links?.getInitialLink().catchError((_) => null);
  final openVoice = initialLink?.host == 'voice';

  final state = AppState(appVersion: info.version);
  unawaited(state.loadThemeMode());
  // The stream replays the launch link once when we start listening; skip only that replay
  // (it is already handled by `openVoice`). Every later tap is the same URI, so comparing
  // against `initialLink` would ignore repeat taps on the shortcut.
  var replayPending = initialLink != null;
  links?.uriLinkStream.listen((uri) {
    if (replayPending) {
      replayPending = false;
      if (uri == initialLink) return;
    }
    final resetCode = passwordResetCode(uri);
    if (resetCode != null) {
      _openPasswordReset(resetCode);
    } else if (uri.host == 'voice') {
      state.requestVoice();
    }
  });
  // The password reset link in the email (https://garad.ai/forgot-password/retrieve/…) started the app.
  final launchResetCode = initialLink == null ? null : passwordResetCode(initialLink);
  if (launchResetCode != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPasswordReset(launchResetCode));
  }

  final auth = AuthState(GaradApi());
  unawaited(auth.restore());
  // Settings → Notifications ("Responses"): ready before the first answer.
  unawaited(GaradNotifications.init());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: GaradApp(openVoice: openVoice),
    ),
  );
}

final _navigator = GlobalKey<NavigatorState>();

/// "Choose a new password" over whatever is showing (the sign-in screen, or a chat).
void _openPasswordReset(String code) {
  final navigator = _navigator.currentState;
  if (navigator == null) {
    // Not built yet: try again after the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPasswordReset(code));
    return;
  }
  navigator.push(MaterialPageRoute<void>(builder: (_) => ResetPasswordScreen(code: code)));
}

/// Login screen when signed out, the chat list when signed in.
class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.openVoice});

  final bool openVoice;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (!auth.ready) return const Scaffold();
    FlutterNativeSplash.remove();
    // Keyed by user so signing out and in again starts fresh.
    return auth.signedIn
        ? ChatScreen(key: ValueKey(auth.user!.id), startVoice: openVoice)
        : const WelcomeScreen();
  }
}

class GaradApp extends StatelessWidget {
  const GaradApp({super.key, required this.openVoice});

  final bool openVoice;

  ThemeData _theme(Palette c, Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.brand,
      brightness: brightness,
      surface: c.background,
    ),
    scaffoldBackgroundColor: c.background,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Garad AI',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: _theme(Palette.light, Brightness.light),
      darkTheme: _theme(Palette.dark, Brightness.dark),
      themeMode: context.select<AppState, ThemeMode>((s) => s.themeMode),
      // In a browser, the page behind the app (Safari's top edge) takes the app's background colour.
      builder: (context, child) {
        setBrowserColor(Theme.of(context).scaffoldBackgroundColor);
        return child!;
      },
      home: _AuthGate(openVoice: openVoice),
    );
  }
}
