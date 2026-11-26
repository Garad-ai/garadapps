import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;

import '../chat_strings.dart';
import 'billing.dart';
import 'http_client.dart';
import 'models.dart';

/// The Garad website's mobile API (routes/api.php "mobile" group in the website code): the app runs on
/// the website's own backend — same accounts, Chat Pro engine, models, credits, memory, tools, tasks.
/// The phone app uses the live site (garad.ai) unless told otherwise. To test against the local XAMPP
/// copy of the website instead (its own database and accounts):
///
///   flutter run --dart-define=API_URL=http://10.0.2.2/garad.ai/public/api/mobile        (Android emulator)
///   flutter run --dart-define=API_URL=http://192.168.1.20/garad.ai/public/api/mobile    (phone on this PC's Wi-Fi)
///
/// The web test build is served from the local copy, so it keeps using it (the live site does not
/// accept calls from other web addresses).
const String _apiUrlSetting = String.fromEnvironment('API_URL');

const String liveApiUrl = 'https://garad.ai/api/mobile';

String get apiBaseUrl {
  if (_apiUrlSetting.isNotEmpty) return _apiUrlSetting.replaceAll(RegExp(r'/+$'), '');
  if (kIsWeb) return 'http://localhost/garad.ai/public/api/mobile';
  return liveApiUrl;
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
  GaradApi({http.Client? client}) : _client = client ?? createHttpClient();

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

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);

  // ---- Auth ----

  /// Sign in with email and password (the same accounts and passwords as garad.ai).
  Future<({String token, GaradUser user})> login(String email, String password) async {
    final data = await _send(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password, 'device_name': _deviceName},
    ) as Map<String, dynamic>;
    return (token: data['token'] as String, user: GaradUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  /// Sign up: one "Full name" (the server splits it into the website's first name and surname),
  /// email and password.
  Future<({String token, GaradUser user})> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final data = await _send(
      'POST',
      '/auth/register',
      body: {'full_name': fullName, 'email': email, 'password': password, 'device_name': _deviceName},
    ) as Map<String, dynamic>;
    return (token: data['token'] as String, user: GaradUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  /// "Forgot password?": emails the website's link to set a new password. Returns the server's message,
  /// which is the same whether or not the email has an account.
  Future<String> forgotPassword(String email) async {
    final data = await _send('POST', '/auth/forgot-password', body: {'email': email}) as Map<String, dynamic>;
    return data['message'] as String? ?? '';
  }

  /// The reset link from that email opened the app: saves the new password (the link works once and
  /// for an hour) and signs this phone in. Other phones signed in to the account are signed out.
  Future<({String token, GaradUser user})> resetPassword({required String code, required String password}) async {
    final data = await _send(
      'POST',
      '/auth/reset-password',
      body: {'code': code, 'password': password, 'password_confirmation': password, 'device_name': _deviceName},
    ) as Map<String, dynamic>;
    return (token: data['token'] as String, user: GaradUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  /// Chat without an account: this phone's guest login (the server limits messages per day).
  Future<({String token, GaradUser user})> guest(String deviceId) async {
    final data = await _send(
      'POST',
      '/auth/guest',
      body: {'device_id': deviceId, 'device_name': _deviceName},
    ) as Map<String, dynamic>;
    return (token: data['token'] as String, user: GaradUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  /// The server's Google OAuth *web* client ID (public), passed to Google as "serverClientId" so the
  /// ID token is made for our server. Null when Google sign-in isn't set up there. Asked once.
  Future<String?> googleClientId() => _googleClientId ??= () async {
    try {
      final data = await _send('GET', '/auth/google') as Map<String, dynamic>;
      final id = (data['client_id'] as String?)?.trim();
      return (id == null || id.isEmpty) ? null : id;
    } catch (_) {
      _googleClientId = null; // try again next time (e.g. was offline)
      rethrow;
    }
  }();
  Future<String?>? _googleClientId;

  /// "Continue with Google": the server checks Google's ID token and signs in (or creates) the account.
  Future<({String token, GaradUser user})> googleLogin(String idToken) async {
    final data = await _send(
      'POST',
      '/auth/google',
      body: {'id_token': idToken, 'device_name': _deviceName},
    ) as Map<String, dynamic>;
    return (token: data['token'] as String, user: GaradUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  Future<void> logout() => _send('POST', '/auth/logout');

  Future<GaradUser> me() async {
    final data = await _send('GET', '/me') as Map<String, dynamic>;
    return GaradUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  // ---- Settings → Profile and Data controls (the website's own rules) ----

  /// New name (one Full name box, like sign-up) and phone ("" removes it).
  Future<GaradUser> updateProfile({required String fullName, required String phone}) async {
    final data = await _send('PATCH', '/me', body: {'full_name': fullName, 'phone': phone}) as Map<String, dynamic>;
    return GaradUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// [current] may be empty for an account made with Google (it has no password anyone knows).
  Future<String> changePassword({required String current, required String password, String? googleIdToken}) async {
    final data = await _send(
      'POST',
      '/me/password',
      body: {
        if (current.isNotEmpty) 'current_password': current,
        'google_id_token': ?googleIdToken,
        'password': password,
        'password_confirmation': password,
      },
    ) as Map<String, dynamic>;
    return data['message'] as String? ?? '';
  }

  /// The website's account deletion request (the admin reviews it). Confirmed with the password, or
  /// for a Google account with a fresh Google sign-in ([googleIdToken]).
  Future<String> requestAccountDeletion({String? password, String? googleIdToken}) async {
    final data = await _send(
      'POST',
      '/me/delete-request',
      body: {'password': ?password, 'google_id_token': ?googleIdToken},
    ) as Map<String, dynamic>;
    return data['message'] as String? ?? '';
  }

  /// Deletes every chat in the side menu (Data controls → Delete all chats).
  Future<void> deleteAllConversations() async {
    await _send('DELETE', '/conversations');
    cachedChats = null;
    cachedConversations.clear();
  }

  // ---- Models and chats ----

  // ---- Last results, kept in memory so screens open instantly and refresh behind the scenes ----

  /// The last model list.
  List<ChatModelInfo>? cachedModels;

  /// The side menu's last pinned and recent chats (first page, no search).
  ({List<ConversationSummary> pinned, List<ConversationSummary> recents, int? nextPage})? cachedChats;

  /// The last messages seen in each chat.
  final Map<int, ({ConversationSummary conversation, List<ChatMessage> messages})> cachedConversations = {};

  /// The Scheduled screen's last task list.
  List<ScheduledTask>? cachedTasks;

  /// Forgets everything (sign-out or another account).
  void clearCache() {
    cachedTasks = null;
    cachedBilling = null;
    cachedModels = null;
    cachedChats = null;
    cachedConversations.clear();
  }

  Future<List<ChatModelInfo>> models() async {
    final data = await _send('GET', '/models') as Map<String, dynamic>;
    return cachedModels = [for (final m in data['data'] as List) ChatModelInfo.fromJson(m as Map<String, dynamic>)];
  }

  /// The user's chats, newest first. [search] matches titles and message text.
  Future<({List<ConversationSummary> items, int? nextPage})> conversations({
    int page = 1,
    String? search,
    bool pinnedOnly = false,
  }) async {
    final data = await _send(
      'GET',
      '/conversations',
      query: {
        'page': '$page',
        if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
        if (pinnedOnly) 'pinned': '1',
      },
    ) as Map<String, dynamic>;
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
    final result = (
      conversation: ConversationSummary.fromJson(data),
      messages: [for (final m in data['messages'] as List) ChatMessage.fromJson(m as Map<String, dynamic>)],
    );
    cachedConversations[id] = (conversation: result.conversation, messages: List.of(result.messages));
    return result;
  }

  Future<ConversationSummary> updateConversation(int id, {String? title, bool? pinned}) async {
    final data = await _send(
      'PATCH',
      '/conversations/$id',
      body: {'title': ?title, 'is_pinned': ?pinned},
    ) as Map<String, dynamic>;
    return ConversationSummary.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteConversation(int id) async {
    await _send('DELETE', '/conversations/$id');
    cachedConversations.remove(id);
  }

  /// The id in a file card's website link (…/chat/pro/artifacts/{id}/download).
  static int? documentId(String url) =>
      int.tryParse(RegExp(r'/artifacts/(\d+)/download').firstMatch(url)?.group(1) ?? '');

  /// The bytes of a document the AI created.
  Future<Uint8List> downloadDocument(int id) async {
    final http.Response response;
    try {
      response = await _client
          .get(_uri('/artifacts/$id'), headers: {..._headers}..remove('Content-Type'))
          .timeout(const Duration(minutes: 2));
    } on TimeoutException {
      throw ApiException(chatStrings.timeout);
    } catch (_) {
      throw ApiException(chatStrings.cannotConnect);
    }
    if (response.statusCode != 200) {
      _decode(response.statusCode, response.body);
      throw ApiException(chatStrings.somethingWrong, statusCode: response.statusCode);
    }
    return response.bodyBytes;
  }

  /// The AI voices for calls (five people, different ages and accents).
  /// The picture beside the website's sign-in (video, slides…), for the first screen. Null when it
  /// can't be had — the first screen then shows just the Garad logo.
  Future<WelcomeVisual?> welcomeVisual() async {
    try {
      final data = await _send('GET', '/welcome');
      return data is Map<String, dynamic> ? WelcomeVisual.fromJson(data) : null;
    } on ApiException {
      return null;
    }
  }

  // ---- Billing: the website's plans and EVC Plus checkout ----

  Future<List<GaradPlan>> plans() async {
    final data = await _send('GET', '/plans') as Map<String, dynamic>;
    return [for (final p in data['data'] as List? ?? const []) GaradPlan.fromJson(p as Map<String, dynamic>)];
  }

  Future<List<PaymentMethod>> paymentMethods() async {
    final data = await _send('GET', '/payments/methods') as Map<String, dynamic>;
    return [for (final m in data['data'] as List? ?? const []) PaymentMethod.fromJson(m as Map<String, dynamic>)];
  }

  Future<BillingStatus> billing() async =>
      cachedBilling = BillingStatus.fromJson(await _send('GET', '/billing') as Map<String, dynamic>);

  /// The last plan seen (Settings shows "Free" / "Professional" under the name at once).
  BillingStatus? cachedBilling;

  /// Pays for [planId] with EVC Plus: the phone gets a request to approve with the EVC PIN, and the
  /// answer comes once it is approved (or refused). Returns the server's message ("… plan activated.").
  Future<String> checkout({required String planId, required String method, required String phone, int? seats}) async {
    final data = await _send(
      'POST',
      '/payments/checkout',
      body: {'planId': planId, 'method': method, 'phone': phone, 'seats': ?seats},
      // The person approves the payment on their phone first.
      timeout: const Duration(minutes: 3),
    ) as Map<String, dynamic>;
    return data['message'] as String? ?? '';
  }

  Future<List<AiVoice>> voices() async {
    final data = await _send('GET', '/voices') as Map<String, dynamic>;
    return [for (final v in data['data'] as List) AiVoice.fromJson(v as Map<String, dynamic>)];
  }

  /// A short-lived key for a Garad Live call (OpenAI's realtime model). The server keeps the real
  /// OpenAI key; this one only works to start one call within a few minutes.
  Future<LiveKey> liveSession({String? voice, required bool somali}) async {
    final data = await _send(
      'POST',
      '/live/session',
      body: {'voice': ?voice, 'language': somali ? 'so' : 'en'},
    ) as Map<String, dynamic>;
    return LiveKey(key: data['key'] as String, model: data['model'] as String);
  }

  /// [text] spoken by the AI voice [voiceId], as MP3 (made by the server; the voice key stays there).
  Future<Uint8List> speech(String voiceId, String text) async {
    final http.Response response;
    try {
      response = await _client
          .post(_uri('/speech'), headers: _headers, body: jsonEncode({'voice': voiceId, 'text': text}))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException(chatStrings.timeout);
    } catch (_) {
      throw ApiException(chatStrings.cannotConnect);
    }
    if (response.statusCode != 200) {
      _decode(response.statusCode, response.body);
      throw ApiException(chatStrings.somethingWrong, statusCode: response.statusCode);
    }
    return response.bodyBytes;
  }

  /// Images and documents created in chats, newest first.
  Future<({List<LibraryImage> images, List<LibraryFile> files})> library() async {
    final data = await _send('GET', '/library') as Map<String, dynamic>;
    return (
      images: [for (final item in data['data'] as List) LibraryImage.fromJson(item as Map<String, dynamic>)],
      files: [
        for (final item in data['files'] as List? ?? const []) LibraryFile.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  /// Artifacts: the apps and websites the AI built in chats, newest first (latest version of each).
  final Map<String, Future<List<WebPhoto>>> _webPhotos = {};

  /// Pictures for one idea in an answer; asked once per query while the app runs.
  Future<List<WebPhoto>> photos(String query) => _webPhotos.putIfAbsent(query, () async {
    try {
      // A new picture is made by the AI on the server (about 15 s, longer when several at once).
      final data = await _send(
        'GET',
        '/images',
        query: {'q': query},
        timeout: const Duration(minutes: 2),
      ) as Map<String, dynamic>;
      return [
        for (final item in data['data'] as List)
          if (item is Map<String, dynamic>) WebPhoto.fromJson(item),
      ].where((p) => p.url.isNotEmpty).toList();
    } catch (_) {
      _webPhotos.remove(query); // try again next time
      return const <WebPhoto>[];
    }
  });

  Future<List<BuiltApp>> apps() async {
    final data = await _send('GET', '/apps') as Map<String, dynamic>;
    return [for (final item in data['data'] as List) BuiltApp.fromJson(item as Map<String, dynamic>)];
  }

  /// A created document with its text, for the in-app preview.
  Future<LibraryFile> document(int id) async {
    final data = await _send('GET', '/artifacts/$id/preview') as Map<String, dynamic>;
    return LibraryFile.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// Sends a message and streams the reply. Cancelling the subscription stops listening;
  /// the server still finishes and saves the reply.
  ///
  /// Streams live everywhere (in browsers through `fetch`, see http_client.dart).
  /// [model] is an engine id from [models]; null uses the website admin's default.
  /// [webSearch] turns on the website's web search ("realtime") for this message.
  /// [images]: references from [uploadImage] (a photo, or what the camera sees in a video call).
  Stream<ChatEvent> sendMessage(
    int conversationId,
    String content, {
    String? model,
    bool webSearch = false,
    List<String> images = const [],
    bool voiceCall = false,
    ImageEdit? edit,
    List<({String reference, String name})> files = const [],
  }) async* {
    yield* _stream('/conversations/$conversationId/messages', {
      'content': content,
      'model': ?model,
      'timezone': await localTimezone(),
      if (webSearch) 'web_search': true,
      if (images.isNotEmpty) 'images': images,
      // Documents from [uploadFile]: the server reads their text for the AI.
      if (files.isNotEmpty)
        'files': [
          for (final f in files) {'reference': f.reference, 'name': f.name},
        ],
      // A live voice call: the server asks for short, spoken-style answers.
      if (voiceCall) 'voice_call': true,
      // The Edit screen: change this image of the chat (only the painted area, when there is one).
      if (edit != null) ...{
        'edit_image_url': edit.imageUrl,
        if (edit.mask != null) 'edit_mask': 'data:image/png;base64,${base64Encode(edit.mask!)}',
        'edit_size': ?edit.size,
      },
    });
  }

  /// Uploads a photo to the website's private chat storage; returns its reference for [sendMessage].
  /// The name and type follow the picture's real format (the server checks they match).
  Future<String> uploadImage(Uint8List bytes) async {
    final name = imageName(bytes);
    final mime = switch (name.split('.').last) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    final data = await _send(
      'POST',
      '/attachments',
      body: {'name': name, 'data': 'data:$mime;base64,${base64Encode(bytes)}'},
    ) as Map<String, dynamic>;
    return data['reference'] as String;
  }

  /// Uploads a document (PDF, Word, Excel, PowerPoint, text, CSV…) to the website's private chat
  /// storage; returns its reference for [sendMessage]'s `files`. The server checks the real type.
  Future<String> uploadFile(Uint8List bytes, String name) async {
    final data = await _send(
      'POST',
      '/attachments',
      body: {'name': name, 'data': 'data:application/octet-stream;base64,${base64Encode(bytes)}'},
    ) as Map<String, dynamic>;
    return data['reference'] as String;
  }

  /// A file name whose extension matches the picture's real format: photo.png / .webp / .gif / .jpg.
  static String imageName(Uint8List b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'photo.png';
    if (b.length > 11 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'photo.webp';
    if (b.length > 2 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'photo.gif';
    return 'photo.jpg';
  }

  /// Photos sent in chats, by attachment id, kept while the app runs (they do not change).
  final Map<String, Future<Uint8List>> _photos = {};

  /// A photo the user sent with a message (from [ChatMessage.imageIds]).
  Future<Uint8List> photo(String id) => _photos.putIfAbsent(id, () async {
    final http.Response response;
    try {
      response = await _client
          .get(_uri('/attachments/$id'), headers: {..._headers}..remove('Content-Type'))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      _photos.remove(id); // try again next time
      throw ApiException(chatStrings.cannotConnect);
    }
    if (response.statusCode != 200) {
      _photos.remove(id);
      throw ApiException(chatStrings.somethingWrong, statusCode: response.statusCode);
    }
    return response.bodyBytes;
  });

  /// A new answer to the chat's latest question, replacing the old one (the server keeps the old
  /// answer if this fails). Same events as [sendMessage], without [UserMessageSaved].
  Stream<ChatEvent> regenerate(int conversationId, int messageId, {String? model}) async* {
    yield* _stream('/conversations/$conversationId/messages/$messageId/regenerate', {
      'model': ?model,
      'timezone': await localTimezone(),
    });
  }

  /// One turn of a voice/camera call (POST /call/turn): straight to Claude, without the chat's tools
  /// and memory, so the first words come back fast. [history] is the call so far (oldest first) and
  /// [images] what goes with the words — the camera's view now, a shared photo — sent inline (no
  /// upload first). The server saves the turn to [conversationId]. Yields the answer piece by piece;
  /// cancelling the subscription stops it.
  ///
  /// [cameraOn]: the user just turned the camera on — Garad speaks first about what it sees in
  /// [images] ("Hey, I can see you…"); [text] is not used and the turn is not saved as a message.
  /// [liveCamera]: the last of [images] is what the camera shows right now — Garad can point at
  /// things in it ([CallPoint]s, circled on the video).
  Stream<CallEvent> callTurn(
    int conversationId,
    String text, {
    List<({String role, String text})> history = const [],
    List<Uint8List> images = const [],
    String? model,
    String? language,
    bool cameraOn = false,
    bool liveCamera = false,
  }) async* {
    final pictures = [
      for (final b in images)
        if (_callImageType(b) case final type?) 'data:$type;base64,${base64Encode(b)}',
    ];
    final request = http.Request('POST', _uri('/call/turn'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'conversation_id': conversationId,
        if (cameraOn) 'kind': 'camera_on' else 'text': text,
        if (history.isNotEmpty)
          'history': [
            for (final h in history) {'role': h.role, 'text': h.text},
          ],
        if (pictures.isNotEmpty) 'images': pictures,
        if (liveCamera && pictures.isNotEmpty) 'live_camera': true,
        'model': ?model,
        'language': ?language,
        'timezone': await localTimezone(),
      });

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

    // "event: delta / point / done / error" then "data: {json}" per frame.
    var event = '';
    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
        continue;
      }
      if (!line.startsWith('data:')) continue;
      final json = _tryJson(line.substring(5).trim());
      if (json is! Map) continue;
      switch (event) {
        case 'delta':
          final piece = json['text'];
          if (piece is String && piece.isNotEmpty) yield CallWords(piece);
        case 'point':
          final (x, y) = (json['x'], json['y']);
          if (x is num && y is num) {
            yield CallPoint(x.toDouble().clamp(0, 1), y.toDouble().clamp(0, 1), '${json['label'] ?? ''}'.trim());
          }
        case 'error':
          throw ApiException(json['message'] is String ? json['message'] as String : chatStrings.somethingWrong);
        case 'done':
          return;
      }
    }
  }

  /// The picture type the call accepts (JPEG, PNG, WebP), or null for anything else.
  static String? _callImageType(Uint8List bytes) => switch (imageName(bytes).split('.').last) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'jpg' => 'image/jpeg',
    _ => null,
  };

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

    // The website's Chat Pro stream: "event: <name>" then "data: <payload>" per frame.
    //   message → the saved message id · data → a piece of the answer (raw text, "<br/>" = newline)
    //   title → {"chat_id","title"} · error → {"message","code"} · clear_content → start the answer over
    //   tool_status → {"tool","state","label"} (creating an image, a PDF…) · stop → "[DONE]".
    //   Other events (suggestions, artifact…) are not used: files arrive as cards inside the answer.
    var event = 'data';
    var raw = ''; // the whole answer so far, as sent
    var shown = 0; // characters of the visible answer already passed on
    int? messageId;
    var failed = false;
    final taskIds = <int>{};

    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
        continue;
      }
      if (!line.startsWith('data:')) continue;
      final data = line.length > 5 && line[5] == ' ' ? line.substring(6) : line.substring(5);

      switch (event) {
        case 'message':
          messageId = int.tryParse(data.trim());
          if (messageId != null) {
            yield UserMessageSaved(ChatMessage(id: messageId, role: 'user', content: ''));
          }
        case 'data':
          raw += data.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
          // The website's scheduled-task tool puts a ```garad-task {json}``` block in the answer: show it as a card.
          for (final match in _taskBlock.allMatches(raw)) {
            final json = _tryJson(match.group(1)!.trim());
            if (json is Map<String, dynamic> && json['id'] is int && taskIds.add(json['id'] as int)) {
              yield TaskCreated(ScheduledTask.fromJson(json));
            }
          }
          final visible = _visibleAnswer(raw);
          if (visible.length > shown) {
            yield ReplyDelta(visible.substring(shown));
            shown = visible.length;
          }
        case 'clear_content':
          raw = '';
          shown = 0;
          yield const ReplyReset();
        case 'tool_status':
          final json = _tryJson(data);
          if (json is Map && json['tool'] is String) {
            yield ToolStatus(
              tool: json['tool'] as String,
              state: json['state'] as String? ?? 'working',
              label: json['label'] as String? ?? '',
            );
          }
        case 'title':
          final json = _tryJson(data);
          final title = json is Map ? json['title'] : null;
          if (title is String && title.isNotEmpty) yield TitleUpdated(title);
        case 'error':
          final json = _tryJson(data);
          failed = true;
          yield ReplyFailed(
            json is Map && json['message'] is String ? json['message'] as String : chatStrings.somethingWrong,
            null,
          );
        case 'stop':
          if (!failed) {
            yield ReplyDone(
              ChatMessage(id: messageId, role: 'assistant', content: _visibleAnswer(raw, finished: true)),
            );
          }
          return;
      }
    }
    // The connection ended without "stop": keep what arrived.
    if (!failed && raw.isNotEmpty) {
      yield ReplyDone(ChatMessage(id: messageId, role: 'assistant', content: _visibleAnswer(raw, finished: true)));
    }
  }

  /// The answer without the website's hidden blocks (":::meta {...} :::" with suggestions and the like).
  /// While streaming, a trailing ":" / "::" / ":::me…" is held back until we know whether a block starts.
  static String _visibleAnswer(String raw, {bool finished = false}) {
    // Task cards are shown separately (TaskCreated), so their ```garad-task``` blocks are hidden.
    var source = raw.replaceAll(_taskBlock, '');
    if (!finished) {
      // An unfinished ```garad-task block: wait for the rest before showing anything after it.
      final open = source.indexOf('```garad');
      if (open >= 0) source = source.substring(0, open);
    }
    final block = RegExp(r':::[a-zA-Z]').firstMatch(source);
    var text = block == null ? source : source.substring(0, block.start);
    if (block == null && !finished) {
      // Also held back: the start of a file card (<div …>) or an image marker ([[GARAD_…]]) until it is whole.
      final card = text.lastIndexOf('<div');
      if (card >= 0 && !text.substring(card).contains('</div>')) text = text.substring(0, card);
      final marker = text.lastIndexOf('[[');
      if (marker >= 0 && !text.substring(marker).contains(']]')) text = text.substring(0, marker);
      final partial = RegExp(r'(:{1,3}[a-zA-Z]{0,8}|`{1,3}[a-z-]{0,12}|<d?i?v?|\[)$').firstMatch(text);
      if (partial != null) text = text.substring(0, partial.start);
    }
    return finished ? text.trim() : text;
  }

  /// A ```garad-task {json}``` block (the website's scheduled-task card), with its JSON as group 1.
  static final _taskBlock = RegExp(r'```garad-task\s*\n([\s\S]*?)\n?```');

  static Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  // ---- Scheduled tasks ----

  /// [filter]: all | upcoming | active | paused | completed | failed.
  Future<({List<ScheduledTask> items, Map<String, int> counts})> tasks({String filter = 'all', String? search}) async {
    final data = await _send(
      'GET',
      '/tasks',
      query: {'filter': filter, if (search != null && search.trim().isNotEmpty) 'q': search.trim()},
    ) as Map<String, dynamic>;
    final items = [for (final t in data['data'] as List) ScheduledTask.fromJson(t as Map<String, dynamic>)];
    if (filter == 'all' && (search == null || search.trim().isEmpty)) cachedTasks = items;
    return (
      items: items,
      counts: {
        for (final e in (data['counts'] as Map<String, dynamic>? ?? {}).entries) e.key: (e.value as num).toInt(),
      },
    );
  }

  /// "Schedule a task" box: the AI reads [text] ("every day at 3pm remind me…") and creates the task.
  /// Throws [ApiException] with the AI's question when the request has no time.
  Future<ScheduledTask> createTask(String text) async {
    final data =
        await _send('POST', '/tasks', body: {'text': text, 'timezone': await localTimezone()}) as Map<String, dynamic>;
    return ScheduledTask.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// [status]: active | paused.
  Future<ScheduledTask> setTaskStatus(int id, String status) async {
    final data = await _send('PATCH', '/tasks/$id', body: {'status': status}) as Map<String, dynamic>;
    return ScheduledTask.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteTask(int id) => _send('DELETE', '/tasks/$id');

  /// Asks the server to fire due reminders now (only does something on servers without cron).
  /// True when the scheduler actually ran (so task statuses may have changed).
  Future<bool> runDueTasks() async {
    try {
      final data = await _send('POST', '/tasks/run-due');
      return data is Map && data['ran'] == true;
    } on ApiException {
      // Best effort: the next check tries again.
      return false;
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

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration timeout = _timeout,
  }) async {
    final request = http.Request(method, _uri(path, query))..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(timeout));
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
      if (errors is Map &&
          errors.isNotEmpty &&
          errors.values.first is List &&
          (errors.values.first as List).isNotEmpty) {
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
