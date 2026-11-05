import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'api/garad_api.dart';
import 'app_state.dart';
import 'auth_state.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  // Drop-in replacement for WidgetsFlutterBinding.ensureInitialized(): lets the running app
  // simulate other devices (size, notch, text scale, …) from DevTools. Off in release builds.
  final binding = DevicePreview.enable();

  // In Chrome or on a desktop, start inside a phone frame so the layout looks like the real
  // app. On a real phone, no preset: the device's own screen is the one to test.
  final preview = DevicePreview.maybeController;
  final onBigScreen =
      kIsWeb ||
      const {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);
  if (preview != null && onBigScreen) {
    unawaited(preview.applyPreset(DevicePresets.galaxyS24));
  }
  // The splash screen stays up until the saved login has been read (see _AuthGate).
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  final info = await PackageInfo.fromPlatform();

  // `garadai://voice` (the "Talk to Garad" shortcut): open Chat Pro straight into Voice.
  final links = kIsWeb ? null : AppLinks();
  final initialLink = await links?.getInitialLink().catchError((_) => null);
  final openVoice = initialLink?.host == 'voice';

  final state = AppState(appVersion: info.version);
  // The stream replays the launch link once when we start listening; skip only that replay
  // (it is already handled by `openVoice`). Every later tap is the same URI, so comparing
  // against `initialLink` would ignore repeat taps on the shortcut.
  var replayPending = initialLink != null;
  links?.uriLinkStream.listen((uri) {
    if (replayPending) {
      replayPending = false;
      if (uri == initialLink) return;
    }
    if (uri.host == 'voice') state.requestVoice();
  });

  final auth = AuthState(GaradApi());
  unawaited(auth.restore());

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
        : const LoginScreen();
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
      debugShowCheckedModeBanner: false,
      theme: _theme(Palette.light, Brightness.light),
      darkTheme: _theme(Palette.dark, Brightness.dark),
      home: _AuthGate(openVoice: openVoice),
    );
  }
}
