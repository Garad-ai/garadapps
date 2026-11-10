import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/api/models.dart';
import 'package:garad_ai/widgets/chat_search_sheet.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('search shows recents, filters as you type, and opens the tapped chat', (tester) async {
    const chats = [
      {'id': 1, 'title': 'Online document business ideas'},
      {'id': 2, 'title': 'Greeting exchange'},
    ];
    // A fake server: /conversations?q=… returns the chats whose title contains q.
    final api = GaradApi(
      client: MockClient((request) async {
        final q = (request.url.queryParameters['q'] ?? '').toLowerCase();
        final items = chats.where((c) => (c['title']! as String).toLowerCase().contains(q)).toList();
        return http.Response(jsonEncode({'data': items, 'next_page': null}), 200);
      }),
    );
    ConversationSummary? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showChatSearch(context, api: api, onSelect: (chat) => opened = chat),
            child: const Text('search'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('search'));
    await tester.pumpAndSettle();

    // Recents, each with the round chat icon.
    expect(find.text('Recents'), findsOneWidget);
    expect(find.text('Greeting exchange'), findsOneWidget);
    expect(find.byType(ChatBubbleIcon), findsNWidgets(2));

    // Typing narrows the list (after the short pause).
    await tester.enterText(find.byType(TextField), 'business');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Greeting exchange'), findsNothing);
    expect(find.text('Online document business ideas'), findsOneWidget);

    // Tapping a chat closes the search and opens that chat.
    await tester.tap(find.text('Online document business ideas'));
    await tester.pumpAndSettle();
    expect(opened?.id, 1);
    expect(find.byType(TextField), findsNothing);
  });
}
