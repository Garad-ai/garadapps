import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/api/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The call endpoint (POST /call/turn, MobileCallController::turn): the turn goes out with its
/// history and pictures inline, and the answer comes back as `delta` (words) and `point` (where
/// Garad points on the camera) frames, cut into small network chunks the way it really arrives.
GaradApi _apiReplying(String body, {int status = 200, void Function(Map<String, dynamic> sent)? onSend}) => GaradApi(
  client: MockClient.streaming((request, _) async {
    onSend?.call(jsonDecode((request as http.Request).body) as Map<String, dynamic>);
    final bytes = utf8.encode(body);
    final chunks = [
      for (var i = 0; i < bytes.length; i += 5) bytes.sublist(i, i + 5 > bytes.length ? bytes.length : i + 5),
    ];
    return http.StreamedResponse(
      Stream.fromIterable(chunks),
      status,
      headers: {'content-type': status == 200 ? 'text/event-stream' : 'application/json'},
    );
  }),
)..token = 'test';

String _words(List<CallEvent> events) => events.whereType<CallWords>().map((e) => e.text).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);
  final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 2]);

  test('streams the answer piece by piece and sends the turn the way the server expects', () async {
    late Map<String, dynamic> sent;
    final api = _apiReplying(
      'event: delta\ndata: {"text":"Hi Afrah,"}\n\n'
      'event: delta\ndata: {"text":" I can see 7 + 2 + 0 — that\'s 9."}\n\n'
      'event: done\ndata: {"message_id":77,"stop_reason":"end_turn"}\n\n',
      onSend: (body) => sent = body,
    );

    final events = await api
        .callTurn(
          5,
          'What is this sum?',
          history: const [(role: 'user', text: 'Hello'), (role: 'assistant', text: 'Hi! How can I help?')],
          images: [jpeg, gif],
          model: 'claude-haiku-5-5',
          language: 'en',
        )
        .toList();

    expect(events.whereType<CallWords>().map((e) => e.text), ['Hi Afrah,', " I can see 7 + 2 + 0 — that's 9."]);
    expect(sent['conversation_id'], 5);
    expect(sent['text'], 'What is this sum?');
    expect(sent['history'], [
      {'role': 'user', 'text': 'Hello'},
      {'role': 'assistant', 'text': 'Hi! How can I help?'},
    ]);
    expect(sent['images'], ['data:image/jpeg;base64,${base64Encode(jpeg)}'], reason: 'inline, and only types the server accepts (no GIF)');
    expect(sent.containsKey('live_camera'), isFalse, reason: 'not a live camera picture unless said so');
    expect(sent['model'], 'claude-haiku-5-5');
    expect(sent['language'], 'en');
  });

  test('where Garad points on the live camera comes between its words, in order', () async {
    late Map<String, dynamic> sent;
    final api = _apiReplying(
      'event: delta\ndata: {"text":"Sure. "}\n\n'
      'event: point\ndata: {"x":0.5445,"y":0.175,"label":"Power button"}\n\n'
      'event: delta\ndata: {"text":"Press the red button at the top."}\n\n'
      'event: point\ndata: {"x":1.4,"y":-0.2,"label":""}\n\n'
      'event: done\ndata: {"message_id":78,"stop_reason":"end_turn"}\n\n',
      onSend: (body) => sent = body,
    );

    final events = await api.callTurn(5, 'How do I turn off my TV?', images: [jpeg], liveCamera: true).toList();

    expect(sent['live_camera'], isTrue);
    expect(_words(events), 'Sure. Press the red button at the top.', reason: 'the points are never part of what is said');
    expect(events[1], isA<CallPoint>().having((p) => p.x, 'x', 0.5445).having((p) => p.y, 'y', 0.175).having((p) => p.label, 'label', 'Power button'));
    final edge = events.whereType<CallPoint>().last;
    expect((edge.x, edge.y), (1.0, 0.0), reason: 'kept inside the picture');
  });

  test('camera turned on: asks Garad to speak first about the picture (no words from the user)', () async {
    late Map<String, dynamic> sent;
    final api = _apiReplying(
      'event: delta\ndata: {"text":"Hi Afrah, I can see a shopping list."}\n\n'
      'event: done\ndata: {"message_id":null,"stop_reason":"end_turn"}\n\n',
      onSend: (body) => sent = body,
    );

    final events = await api.callTurn(5, '', images: [jpeg], cameraOn: true, liveCamera: true).toList();

    expect(_words(events), 'Hi Afrah, I can see a shopping list.');
    expect(sent['kind'], 'camera_on');
    expect(sent.containsKey('text'), isFalse, reason: 'the server words this turn itself');
    expect(sent['images'], hasLength(1));
  });

  test('a failure in the middle of the answer is an error with the server\'s words', () async {
    final api = _apiReplying(
      'event: delta\ndata: {"text":"Let me"}\n\n'
      'event: error\ndata: {"message":"Garad can\'t answer right now. Please try again.","code":"provider_error"}\n\n',
    );
    final events = <CallEvent>[];
    await expectLater(
      api.callTurn(5, 'Hi').forEach(events.add),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', "Garad can't answer right now. Please try again.")),
    );
    expect(_words(events), 'Let me', reason: 'what arrived before the error was still passed on');
  });

  test('a refusal before streaming (no credits) is an error with the server\'s message', () async {
    final api = _apiReplying('{"code":"no_credits","message":"You have no credits left for Garad."}', status: 402);
    await expectLater(
      api.callTurn(5, 'Hi').toList(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'You have no credits left for Garad.')),
    );
  });
}
