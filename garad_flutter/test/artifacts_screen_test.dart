import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/auth_state.dart';
import 'package:garad_ai/chat_strings.dart';
import 'package:garad_ai/screens/app_preview_screen.dart';
import 'package:garad_ai/screens/artifacts_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

const apps = [
  {
    'id': 91,
    'title': 'Hodan Coffee',
    'kind': 'html',
    'source': '<!DOCTYPE html><html><head><title>Hodan Coffee</title></head><body>Menu</body></html>',
    'chat_id': 12,
    'chat_title': 'Coffee shop website',
    'version': 3,
  },
  {
    'id': 80,
    'title': 'Budget Tracker',
    'kind': 'react',
    'source': 'export default function BudgetTracker() { return <div>0</div>; }',
    'chat_id': 7,
    'chat_title': 'Money app',
    'version': 1,
  },
];

/// Artifacts over a chat-like screen, with a fake server answering GET /apps.
Widget artifactsApp({ValueChanged<int>? onOpenChat, void Function(int, String)? onChange}) {
  final server = MockClient((request) async {
    expect(request.url.path, endsWith('/apps'));
    return http.Response(jsonEncode({'data': apps}), 200, headers: {'content-type': 'application/json'});
  });
  return ChangeNotifierProvider.value(
    value: AuthState(GaradApi(client: server)),
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ArtifactsScreen(onOpenChat: onOpenChat ?? (_) {}, onChange: onChange ?? (_, _) {}),
              ),
            ),
            child: const Text('open artifacts'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => AppPreviewScreen.previewBuilder = (page, onError, key) => Text('running app', key: key));

  Future<void> open(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.tap(find.text('open artifacts'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the built apps, newest first, and filters websites / apps', (tester) async {
    await open(tester, artifactsApp());
    expect(find.text(chatStrings.artifacts), findsOneWidget);
    expect(find.text('Hodan Coffee'), findsOneWidget);
    expect(find.text('${chatStrings.websiteKind} · ${chatStrings.appVersion(3)}'), findsOneWidget);
    expect(find.text('Budget Tracker'), findsOneWidget);

    await tester.tap(find.text(chatStrings.apps));
    await tester.pumpAndSettle();
    expect(find.text('Hodan Coffee'), findsNothing);
    expect(find.text('Budget Tracker'), findsOneWidget);
  });

  testWidgets('tap an app to run it; a change asked for there goes to its chat', (tester) async {
    (int, String)? sent;
    await open(tester, artifactsApp(onChange: (chat, change) => sent = (chat, change)));
    await tester.tap(find.text('Hodan Coffee'));
    await tester.pumpAndSettle();
    expect(find.text('running app'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Add opening hours');
    await tester.pump();
    await tester.tap(find.byTooltip(chatStrings.send));
    await tester.pumpAndSettle();
    expect(sent, (12, 'Add opening hours'));
    expect(find.text('open artifacts'), findsOneWidget, reason: 'back in the chat');
  });

  testWidgets('Open chat from the app menu goes to the chat it was built in', (tester) async {
    int? opened;
    await open(tester, artifactsApp(onOpenChat: (id) => opened = id));
    await tester.tap(find.text('Budget Tracker'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(chatStrings.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text(chatStrings.openChat));
    await tester.pumpAndSettle();
    expect(opened, 7);
    expect(find.text('open artifacts'), findsOneWidget);
  });
}
