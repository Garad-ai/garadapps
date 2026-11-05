import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;

import '../chat_strings.dart';
import 'models.dart';

/// Where the Garad backend (garad-api, Laravel) runs. Override at build time:
///
///   flutter run --dart-define=API_URL=http://192.168.1.20/garad-api/public/api
///
/// Defaults: the Android emulator reaches this PC as 10.0.2.2; Chrome and desktop use localhost.
/// A real phone needs this PC's network address (see `ipconfig`).
const String _apiUrlSetting = String.fromEnvironment('API_URL');

String get apiBaseUrl {
  if (_apiUrlSetting.isNotEmpty) return _apiUrlSetting.replaceAll(RegExp(r'/+$'), '');
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2/garad-api/public/api';
  }
  return 'http://localhost/garad-api/public/api';
}

/// A failed API call. [message] is ready to show to the user.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get unauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Talks to the Garad backend. One instance for the whole app; [token] is set after login.
class GaradApi {
  GaradApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? token;

  /// Called when the server says the login is no longer valid (expired, logged out, blocked).
  VoidCallback? onUnauthorized;

  static const _timeout = Duration(seconds: 30);

  Map<String, String> get _headers => {
        // Laravel only answers errors as JSON (instead of redirecting) when asked for JSON.
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);

  // ---- Auth ----

  Future<({String token, GaradUser user})> login(String email, String password) async {
    final data = await _send('POST', '/auth/login', body: {
      'email': email,
      'password': password,
      'device_name': _deviceName,
    }) as Map<String, dynamic>;
    return (token: data['token'] as String, user: GaradUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  Future<({String token, GaradUser user})> register({
    required String name,
    required String surname,
    required String phone,
    required String country,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final data = await _send('POST', '/auth/register', body: {
      'name': name,
      'surname': surname,
      'phone': phone,
      'country': country,
      'email': email,
      'password': password,
      'password_confirmation': passwordConfirmation,
      'device_name': _deviceName,
    }) as Map<String, dynamic>;
    return (token: data['token'] as String, user: GaradUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  Future<void> logout() => _send('POST', '/auth/logout');

  Future<GaradUser> me() async {
    final data = await _send('GET', '/me') as Map<String, dynamic>;
    return GaradUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  // ---- Models and chats ----

  Future<List<ChatModelInfo>> models() async {
    final data = await _send('GET', '/models') as Map<String, dynamic>;
    return [for (final m in data['data'] as List) ChatModelInfo.fromJson(m as Map<String, dynamic>)];
  }

  /// The user's chats, newest first. [search] matches titles and message text.
  Future<({List<ConversationSummary> items, int? nextPage})> conversations({
    int page = 1,
    String? search,
    bool pinnedOnly = false,
  }) async {
    final data = await _send('GET', '/conversations', query: {
      'page': '$page',
      if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
      if (pinnedOnly) 'pinned': '1',
    }) as Map<String, dynamic>;
    return (
      items: [for (final c in data['data'] as List) ConversationSummary.fromJson(c as Map<String, dynamic>)],
      nextPage: data['next_page'] as int?,
    );
  }

  Future<ConversationSummary> createConversation() async {
    final data = await _send('POST', '/conversations', body: <String, Object>{}) as Map<String, dynamic>;
    return ConversationSummary.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<({ConversationSummary conversation, List<ChatMessage> messages})> conversation(int id) async {
    final data = (await _send('GET', '/conversations/$id') as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return (
      conversation: ConversationSummary.fromJson(data),
      messages: [for (final m in data['messages'] as List) ChatMessage.fromJson(m as Map<String, dynamic>)],
    );
  }

  Future<ConversationSummary> updateConversation(int id, {String? title, bool? pinned}) async {
    final data = await _send('PATCH', '/conversations/$id', body: {
      'title': ?title,
      'is_pinned': ?pinned,
    }) as Map<String, dynamic>;
    return ConversationSummary.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteConversation(int id) => _send('DELETE', '/conversations/$id');

  /// Sends a message and streams the reply. Cancelling the subscription stops listening;
  /// the server still finishes and saves the reply.
  ///
  /// Note: in Chrome (Flutter web) the browser HTTP client delivers the whole reply at the
  /// end instead of piece by piece. On Android and iOS it streams live.
  /// [model] is an engine id from [models]; null uses the website admin's default.
  Stream<ChatEvent> sendMessage(int conversationId, String content, {String? model}) async* {
    yield* _stream('/conversations/$conversationId/messages',
        {'content': content, 'model': ?model, 'timezone': await localTimezone()});
  }

  /// A new answer to the chat's latest question, replacing the old one (the server keeps the old
  /// answer if this fails). Same events as [sendMessage], without [UserMessageSaved].
  Stream<ChatEvent> regenerate(int conversationId, int messageId, {String? model}) async* {
    yield* _stream('/conversations/$conversationId/messages/$messageId/regenerate',
        {'model': ?model, 'timezone': await localTimezone()});
  }

  Stream<ChatEvent> _stream(String path, Map<String, Object?> body) async* {
    final request = http.Request('POST', _uri(path))
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_timeout);
    } on TimeoutException {
      throw ApiException(chatStrings.timeout);
    } catch (_) {
      throw ApiException(chatStrings.cannotConnect);
    }

    if (response.statusCode != 200) {
      _decode(response.statusCode, await response.stream.bytesToString());
      throw ApiException(chatStrings.somethingWrong, statusCode: response.statusCode);
    }

    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final Object? event;
      try {
        event = jsonDecode(line.substring(5).trim());
      } on FormatException {
        continue;
      }
      if (event is! Map<String, dynamic>) continue;
      switch (event['type']) {
        case 'user_message':
          yield UserMessageSaved(ChatMessage.fromJson(event['message'] as Map<String, dynamic>));
        case 'delta':
          yield ReplyDelta(event['text'] as String? ?? '');
        case 'done':
          yield ReplyDone(ChatMessage.fromJson(event['message'] as Map<String, dynamic>));
        case 'title':
          final title = event['title'];
          if (title is String && title.isNotEmpty) yield TitleUpdated(title);
        case 'task':
          final task = event['task'];
          if (task is Map<String, dynamic>) yield TaskCreated(ScheduledTask.fromJson(task));
        case 'error':
          final saved = event['saved'];
          yield ReplyFailed(
            event['message'] as String? ?? chatStrings.somethingWrong,
            saved is Map<String, dynamic> ? ChatMessage.fromJson(saved) : null,
          );
      }
    }
  }

  // ---- Scheduled tasks ----

  /// [filter]: all | upcoming | active | paused | completed | failed.
  Future<({List<ScheduledTask> items, Map<String, int> counts})> tasks({String filter = 'all', String? search}) async {
    final data = await _send('GET', '/tasks', query: {
      'filter': filter,
      if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
    }) as Map<String, dynamic>;
    return (
      items: [for (final t in data['data'] as List) ScheduledTask.fromJson(t as Map<String, dynamic>)],
      counts: {
        for (final e in (data['counts'] as Map<String, dynamic>? ?? {}).entries) e.key: (e.value as num).toInt(),
      },
    );
  }

  /// "Schedule a task" box: the AI reads [text] ("every day at 3pm remind me…") and creates the task.
  /// Throws [ApiException] with the AI's question when the request has no time.
  Future<ScheduledTask> createTask(String text) async {
    final data = await _send('POST', '/tasks', body: {'text': text, 'timezone': await localTimezone()})
        as Map<String, dynamic>;
    return ScheduledTask.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// [status]: active | paused.
  Future<ScheduledTask> setTaskStatus(int id, String status) async {
    final data = await _send('PATCH', '/tasks/$id', body: {'status': status}) as Map<String, dynamic>;
    return ScheduledTask.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteTask(int id) => _send('DELETE', '/tasks/$id');

  /// Asks the server to fire due reminders now (only does something on servers without cron).
  Future<void> runDueTasks() async {
    try {
      await _send('POST', '/tasks/run-due');
    } on ApiException {
      // Best effort: the next check tries again.
    }
  }

  /// The phone's IANA timezone (e.g. "Africa/Mogadishu"); the server falls back to Mogadishu.
  static Future<String?> localTimezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return null;
    }
  }

  // ---- Plumbing ----

  Future<Object?> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final request = http.Request(method, _uri(path, query))..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(_timeout));
    } on TimeoutException {
      throw ApiException(chatStrings.timeout);
    } catch (_) {
      throw ApiException(chatStrings.cannotConnect);
    }
    return _decode(response.statusCode, response.body);
  }

  /// Returns the JSON body on success; otherwise throws an [ApiException] with the server's message.
  Object? _decode(int status, String body) {
    Object? json;
    try {
      json = body.isEmpty ? null : jsonDecode(body);
    } on FormatException {
      json = null;
    }
    if (status >= 200 && status < 300) return json;

    if (status == 401) {
      onUnauthorized?.call();
      throw ApiException(chatStrings.sessionExpired, statusCode: status);
    }
    var message = chatStrings.somethingWrong;
    if (json is Map<String, dynamic>) {
      final errors = json['errors'];
      if (errors is Map && errors.isNotEmpty && errors.values.first is List && (errors.values.first as List).isNotEmpty) {
        message = '${(errors.values.first as List).first}';
      } else if (json['message'] is String && (json['message'] as String).isNotEmpty) {
        message = json['message'] as String;
      }
    }
    if (status == 429) message = chatStrings.tooManyRequests;
    throw ApiException(message, statusCode: status);
  }

  String get _deviceName => kIsWeb ? 'web' : defaultTargetPlatform.name;
}
