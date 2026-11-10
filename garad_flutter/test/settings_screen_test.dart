import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/app_state.dart';
import 'package:garad_ai/auth_state.dart';
import 'package:garad_ai/screens/settings_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Settings fits a phone screen and switches the theme', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final app = AppState(appVersion: '1.0.0');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider.value(value: AuthState(GaradApi())),
        ],
        child: MaterialApp(home: SettingsScreen(onOpenScheduled: () {})),
      ),
    );

    expect(find.text('Settings'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Dark'), 200);
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(app.themeMode, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });
}
