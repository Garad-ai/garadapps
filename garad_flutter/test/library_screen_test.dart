import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/auth_state.dart';
import 'package:garad_ai/screens/library_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// The Library screen with a fake server that answers GET /library with [images].
Widget libraryApp(List<Map<String, Object?>> images, {ValueChanged<int>? onOpenChat}) {
  final server = MockClient((request) async {
    expect(request.url.path, endsWith('/library'));
    return http.Response(jsonEncode({'data': images}), 200, headers: {'content-type': 'application/json'});
  });
  return ChangeNotifierProvider.value(
    value: AuthState(GaradApi(client: server)),
    child: MaterialApp(
      home: Builder(
        // A screen underneath, like the chat, so Library can be closed.
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => LibraryScreen(onOpenChat: onOpenChat ?? (_) {})),
            ),
            child: const Text('open library'),
          ),
        ),
      ),
    ),
  );
}

Future<void> openLibrary(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.tap(find.text('open library'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a message when there are no images yet', (tester) async {
    await openLibrary(tester, libraryApp([]));

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Images you create in chats will show up here.'), findsOneWidget);
  });

  testWidgets('shows the images in a grid; tapping one opens it, and Open chat goes to its chat', (tester) async {
    int? openedChat;
    await openLibrary(
      tester,
      libraryApp([
        {'id': 'chat-image-1', 'url': 'https://garad.ai/uploads/logo.png', 'prompt': 'make image logo', 'chat_id': 42},
        {'id': 'chat-image-2', 'url': 'https://garad.ai/uploads/cat.png', 'prompt': 'a cat', 'chat_id': 7},
      ], onOpenChat: (id) => openedChat = id),
    );

    // Two thumbnails in the grid.
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));

    // Full-screen viewer with the prompt.
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.text('make image logo'), findsOneWidget);

    // ⋯ → Open chat closes the viewer and the Library and opens chat 42.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();
    expect(openedChat, 42);
    expect(find.text('open library'), findsOneWidget);
  });

  testWidgets('Documents tab lists created files; tapping one opens the preview', (tester) async {
    final server = MockClient((request) async {
      final body = request.url.path.endsWith('/library')
          ? {
              'data': [],
              'files': [
                {'id': 1, 'title': 'Online Business Idea', 'name': 'plan.pdf', 'kind': 'pdf', 'size': 887058},
              ],
            }
          : {
              'data': {
                'id': 1,
                'title': 'Online Business Idea',
                'name': 'plan.pdf',
                'kind': 'pdf',
                'created_at': '2026-11-07T08:57:00Z',
                'content': '## Overview\n\nA mobile-first marketplace for young Somali freelancers.',
              },
            };
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: AuthState(GaradApi(client: server)),
        child: MaterialApp(home: LibraryScreen(onOpenChat: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(find.text('Online Business Idea'), findsOneWidget);

    await tester.tap(find.text('Online Business Idea'));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);
    expect(find.textContaining('young Somali freelancers'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
  });

  testWidgets('shows the error and a retry button when the server cannot be reached', (tester) async {
    final server = MockClient((_) async => throw const SocketExceptionLike());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: AuthState(GaradApi(client: server)),
        child: MaterialApp(home: LibraryScreen(onOpenChat: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Can't reach Garad. Check your internet connection."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

/// Any failure while sending counts as "can't reach Garad".
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
