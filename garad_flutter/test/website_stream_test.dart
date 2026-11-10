import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:garad_ai/api/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The website's Chat Pro stream (as recorded from GeneratorController::buildStreamedOutput),
/// cut into small network chunks the way it really arrives.
GaradApi _apiReplying(String body) => GaradApi(
  client: MockClient.streaming((request, _) async {
    final bytes = utf8.encode(body);
    final chunks = [
      for (var i = 0; i < bytes.length; i += 7) bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7),
    ];
    return http.StreamedResponse(Stream.fromIterable(chunks), 200, headers: {'content-type': 'text/event-stream'});
  }),
)..token = 'test';

void main() {
  test('reads the website stream: text, <br/>, hidden meta block, title, end', () async {
    const body =
        'event: message\ndata: 31\n\n'
        'event: data\ndata: Salaan\n\n'
        'event: data\ndata: ! Waan fiicanahay.<br/><br/>Adiguna\n\n'
        'event: data\ndata:  sidee tahay?<br/><br/>:\n\n'
        'event: data\ndata: ::meta<br/>{"entities":[],"suggestions":[]}<br/>:::\n\n'
        'event: title\ndata: {"chat_id":18,"title":"Salaan iyo Xaalad"}\n\n'
        'event: stop\ndata: [DONE]\n\n';

    final events = await _apiReplying(body).sendMessage(18, 'hi').toList();
    final text = events.whereType<ReplyDelta>().map((e) => e.text).join();
    final done = events.whereType<ReplyDone>().single.message;

    expect(events.whereType<UserMessageSaved>().single.message.id, 31);
    expect(text, isNot(contains(':::')), reason: 'the meta block is never shown, not even for a moment');
    expect(done.content, 'Salaan! Waan fiicanahay.\n\nAdiguna sidee tahay?');
    expect(done.id, 31);
    expect(events.whereType<TitleUpdated>().single.title, 'Salaan iyo Xaalad');
  });

  test('turns a ```garad-task block into a task card and hides it from the text', () async {
    final task = jsonEncode({
      'id': 8,
      'title': 'Drink water',
      'instructions': 'Time to drink water! 💧',
      'task_type': 'reminder',
      'status': 'active',
      'schedule_type': 'one_time',
      'timezone': 'Africa/Mogadishu',
      'next_run_at': '2026-11-05T08:06:00+00:00',
    });
    final body =
        'event: message\ndata: 33\n\n'
        'event: tool_status\ndata: {"tool":"create_scheduled_task","state":"completed"}\n\n'
        'event: data\ndata: ```garad-task<br/>$task<br/>```<br/>\n\n'
        'event: data\ndata: I\'ll remind you here in 2 minutes. 💧\n\n'
        'event: stop\ndata: [DONE]\n\n';

    final events = await _apiReplying(body).sendMessage(19, 'remind me').toList();

    final card = events.whereType<TaskCreated>().single.task;
    expect(card.id, 8);
    expect(card.title, 'Drink water');
    expect(events.whereType<ReplyDone>().single.message.content, "I'll remind you here in 2 minutes. 💧");
    expect(events.whereType<ReplyDelta>().map((e) => e.text).join(), isNot(contains('garad-task')));
  });

  test('shows the website\'s error message (e.g. a model outside the plan)', () async {
    const body =
        'event: error\n'
        'data: {"type":"error","message":"The selected chat model is not included in your current plan.","code":"chat_model_plan_required"}\n\n'
        'event: stop\ndata: [DONE]\n\n';

    final events = await _apiReplying(body).sendMessage(18, 'hi').toList();

    expect(events.whereType<ReplyFailed>().single.message, contains('not included in your current plan'));
    expect(events.whereType<ReplyDone>(), isEmpty);
  });
}
