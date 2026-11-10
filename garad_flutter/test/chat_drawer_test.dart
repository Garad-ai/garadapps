import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/auth_state.dart';
import 'package:garad_ai/screens/chat_drawer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('long-pressing a chat opens Pin / Rename / Delete', (tester) async {
    final api = GaradApi(
      client: MockClient((request) async {
        final pinned = request.url.queryParameters['pinned'] == '1';
        final items = pinned
            ? []
            : [
                {'id': 1, 'title': 'Afraino Logo'},
                {'id': 2, 'title': 'Greeting'},
              ];
        return http.Response(jsonEncode({'data': items, 'next_page': null}), 200);
      }),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: AuthState(api),
        child: MaterialApp(
          home: Scaffold(
            body: ChatDrawer(
              currentId: null,
              onSelect: (_) {},
              onChanged: (_, {deleted = false, title}) {},
              onOpenScheduled: () {},
              onOpenLibrary: () {},
              onOpenArtifacts: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No ⋯ buttons: the menu opens on a long press, like Claude.
    expect(find.byIcon(Icons.more_horiz), findsNothing);

    await tester.longPress(find.text('Afraino Logo'));
    await tester.pumpAndSettle();
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
