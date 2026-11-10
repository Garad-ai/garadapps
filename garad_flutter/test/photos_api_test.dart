import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/garad_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);

  test('a photo is uploaded with the name and type of its real format', () async {
    final sent = <Map<String, dynamic>>[];
    final api = GaradApi(
      client: MockClient((request) async {
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'reference': '/dashboard/user/ai-chat-pro/attachments/x'}), 201);
      }),
    );

    expect(await api.uploadImage(png), '/dashboard/user/ai-chat-pro/attachments/x');
    await api.uploadImage(jpeg);
    expect(sent[0]['name'], 'photo.png');
    expect(sent[0]['data'], startsWith('data:image/png;base64,'));
    expect(sent[1]['name'], 'photo.jpg');
    expect(sent[1]['data'], startsWith('data:image/jpeg;base64,'));
  });

  test('a document is uploaded under its own name, and sent with the message as a file', () async {
    final bodies = <Map<String, dynamic>>[];
    final api = GaradApi(
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return request.url.path.endsWith('/attachments')
            ? http.Response(jsonEncode({'reference': '/dashboard/user/ai-chat-pro/attachments/doc'}), 201)
            : http.Response('event: stop\ndata: [DONE]\n\n', 200);
      }),
    );

    final reference = await api.uploadFile(Uint8List.fromList(utf8.encode('Hello')), 'report.pdf');
    await api.sendMessage(7, 'Summarize this file.', files: [(reference: reference, name: 'report.pdf')]).drain<void>();

    expect(bodies[0]['name'], 'report.pdf');
    expect(bodies[0]['data'], 'data:application/octet-stream;base64,${base64Encode(utf8.encode('Hello'))}');
    expect(bodies[1]['files'], [
      {'reference': '/dashboard/user/ai-chat-pro/attachments/doc', 'name': 'report.pdf'},
    ]);
  });

  test('a sent photo is fetched signed in, and only once', () async {
    final requests = <http.Request>[];
    final api = GaradApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
      }),
    )..token = 'secret';

    expect(await api.photo('c267691c-b297-4e9f-8956-8c8ae41da39c'), png);
    await api.photo('c267691c-b297-4e9f-8956-8c8ae41da39c');
    expect(requests, hasLength(1), reason: 'kept after the first download');
    expect(requests.single.url.path, endsWith('/attachments/c267691c-b297-4e9f-8956-8c8ae41da39c'));
    expect(requests.single.headers['Authorization'], 'Bearer secret');
  });
}
