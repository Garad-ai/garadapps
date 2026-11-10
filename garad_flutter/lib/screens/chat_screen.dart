import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../ai_image.dart';
import '../american_voice.dart';
import '../api/garad_api.dart';
import '../api/models.dart';
import '../app_state.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../paste_image.dart';
import '../theme.dart';
import '../widgets/model_picker.dart';
import '../widgets/reminder_card.dart';
import '../widgets/task_card.dart';
import 'chat_drawer.dart';
import 'document_screen.dart';
import 'image_edit_screen.dart';
import '../widgets/answer_view.dart';
import 'artifacts_screen.dart';
import 'camera_capture_screen.dart';
import 'library_screen.dart';
import 'scheduled_screen.dart';
import 'voice_mode_screen.dart';

/// The home screen: a new chat with the greeting, or an open chat. The ☰ menu lists all chats.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.startVoice = false});

  /// Opened from the "Talk to Garad" shortcut: start listening straight away.
  final bool startVoice;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final _speech = SpeechToText();
  late FlutterTts _tts;

  final List<ChatMessage> _messages = [];
  List<ChatModelInfo> _models = [];
  int? _conversationId;

  /// The engine chosen in the picker; sent with each message (the server keeps no per-chat model).
  String? _modelId;
  String _title = '';
  bool _loading = false;
  bool _sending = false;
  bool _webSearch = false;

  /// The model for voice calls (fast Claude Haiku by default; see [_openVoiceMode]).
  String? _voiceModelId;

  /// Photos added to the next message (up to [_maxPhotos]); each starts uploading when added.
  final List<_Attachment> _attachments = [];

  /// The edit for the next message sent by [_editImage].
  ImageEdit? _nextEdit;
  static const _maxPhotos = 4;
  late final void Function() _stopPasteListener;

  /// AI voices for calls, and the one chosen (null = the phone's own voice).
  List<AiVoice> _aiVoices = const [];
  String? _aiVoiceId;
  bool _listening = false;
  bool? _speechReady;

  /// Voice conversation: the recognised words are sent automatically and the answer is read aloud.
  bool _voiceTurn = false;

  /// The answer being read aloud (its speaker button turns into a stop button).
  ChatMessage? _speaking;
  int _handledVoiceRequest = 0;
  StreamSubscription<ChatEvent>? _reply;

  GaradApi get _api => context.read<AuthState>().api;

  @override
  void initState() {
    super.initState();
    _handledVoiceRequest = context.read<AppState>().voiceRequest;
    _bindTts();
    // Browsers: a pasted image (Ctrl+V / ⌘V, e.g. a screenshot) is added to the message.
    _stopPasteListener = listenForPastedImages((bytes) {
      if (mounted) _attach(bytes);
    });
    _loadModels();
    // "Talk to Garad" starts a fresh voice chat; otherwise reopen the chat that was open last time.
    if (widget.startVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openVoiceMode());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreLastChat());
    }
  }

  @override
  void dispose() {
    _stopPasteListener();
    _poll?.cancel();
    _reply?.cancel();
    _speech.cancel();
    _tts.stop();
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- Chats ----

  Future<void> _loadModels() async {
    // Runs from initState: the last list is used for the first frame (no setState needed yet).
    final cached = _api.cachedModels;
    if (cached != null && _models.isEmpty) _useModels(cached);
    try {
      final models = await _api.models();
      if (mounted) setState(() => _useModels(models));
    } on ApiException {
      // The picker stays hidden (or shows the last list); the server uses its default model.
    }
    // The AI voices for calls (an older server without them: the call keeps the phone's voice).
    try {
      _aiVoices = await _api.voices();
    } on ApiException {
      _aiVoices = const [];
    }
  }

  /// Sets the model list (and a default model). No setState: callers wrap it when needed.
  void _useModels(List<ChatModelInfo> models) {
    _models = models;
    if (_modelId == null || !models.any((m) => m.id == _modelId)) {
      // Claude Sonnet first (Garad's everyday model), then the website's default.
      _modelId =
          (models.where((m) => m.usable && m.id.startsWith('claude-sonnet')).firstOrNull ??
                  models.where((m) => m.isDefault).firstOrNull ??
                  models.where((m) => m.usable).firstOrNull ??
                  models.firstOrNull)
              ?.id;
    }
  }

  /// Shows a chat from the menu, or a fresh one when [chat] is null.
  /// [restoring]: reopening the last chat at start-up; if it is gone, quietly start a new chat.
  Future<void> _openConversation(ConversationSummary? chat, {bool restoring = false}) async {
    await _reply?.cancel();
    await _tts.stop();
    // Seen before: show the last copy straight away, then refresh it below.
    final cached = chat == null ? null : _api.cachedConversations[chat.id];
    setState(() {
      _sending = false;
      _messages
        ..clear()
        ..addAll(cached?.messages ?? const []);
      _conversationId = chat?.id;
      _title = cached?.conversation.title ?? chat?.title ?? '';
      _loading = chat != null && cached == null;
    });
    if (cached != null) _scrollToEnd(jump: true);
    _rememberChat(chat?.id);
    if (chat == null) return;
    try {
      final result = await _api.conversation(chat.id);
      // Gone elsewhere, or a message was sent meanwhile (its reply refreshes the chat itself).
      if (!mounted || _conversationId != chat.id || _sending) return;
      final grew = result.messages.length != _messages.length;
      setState(() {
        _messages
          ..clear()
          ..addAll(result.messages);
        _title = result.conversation.title;
      });
      if (cached == null || grew) _scrollToEnd(jump: true);
      _updatePolling();
    } on ApiException catch (e) {
      if (cached != null && e.statusCode != 404) {
        // Offline or the server is slow: keep showing the last copy.
      } else if (restoring || e.statusCode == 404) {
        // Deleted (here or on the website) or unreachable: start fresh instead of an empty, broken chat.
        if (mounted && _conversationId == chat.id) {
          _api.cachedConversations.remove(chat.id);
          setState(() {
            _conversationId = null;
            _title = '';
            _messages.clear();
          });
          _rememberChat(null);
        }
        if (!restoring) _snack(e.message);
      } else {
        _snack(e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- Live updates: show a reminder in the open chat when it fires ----

  Timer? _poll;

  /// True while this chat has a one-time task due within the last 10 minutes or the next 2 hours —
  /// the scheduler will soon post its result here.
  bool get _awaitingTask {
    final now = DateTime.now();
    return _messages.any(
      (m) => m.tasks.any(
        (t) =>
            t.status == 'active' &&
            !t.recurring &&
            t.nextRunAt != null &&
            t.nextRunAt!.isAfter(now.subtract(const Duration(minutes: 10))) &&
            t.nextRunAt!.isBefore(now.add(const Duration(hours: 2))),
      ),
    );
  }

  /// Checks every 20 s (only while a task is due); reloads the chat when something new arrived.
  void _updatePolling() {
    if (_awaitingTask && _conversationId != null) {
      _poll ??= Timer.periodic(const Duration(seconds: 20), (_) => _refreshQuietly());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Reloads the open chat in the background. [force]: always take the server's version (after an
  /// answer, so ids, task cards and tool results saved by the website's engine show up).
  Future<void> _refreshQuietly({bool force = false}) async {
    final id = _conversationId;
    if (id == null || _sending || _loading || !mounted) return;
    try {
      // A reminder is due: let the server fire it first (no-op where cron already does this).
      final now = DateTime.now();
      final due = _messages.any(
        (m) => m.tasks.any(
          (t) =>
              t.status == 'active' && t.nextRunAt != null && !t.nextRunAt!.isAfter(now.add(const Duration(seconds: 5))),
        ),
      );
      if (due) await _api.runDueTasks();
      if (!mounted || _conversationId != id) return;
      final result = await _api.conversation(id);
      if (!mounted || _conversationId != id || _sending) return;
      final before = _messages.length;
      final statusChanged = result.messages
          .expand((m) => m.tasks)
          .any(
            (fresh) => _messages.expand((m) => m.tasks).any((old) => old.id == fresh.id && old.status != fresh.status),
          );
      if (force || result.messages.length != before || statusChanged) {
        setState(() {
          _messages
            ..clear()
            ..addAll(result.messages);
        });
        if (result.messages.length > before) _scrollToEnd();
      }
    } on ApiException {
      // Offline for a moment: try again on the next tick.
    }
    _updatePolling();
  }

  // ---- Reopen the last chat after a refresh / restart ----

  static const _storage = FlutterSecureStorage();

  String? get _lastChatKey {
    final userId = context.read<AuthState>().user?.id;
    return userId == null ? null : 'garad_last_chat_$userId';
  }

  void _rememberChat(int? id) {
    final key = _lastChatKey;
    if (key == null) return;
    // Best effort: failing to remember only means the next start shows a new chat.
    (id == null ? _storage.delete(key: key) : _storage.write(key: key, value: '$id')).catchError((_) {});
  }

  Future<void> _restoreLastChat() async {
    final key = _lastChatKey;
    if (key == null) return;
    String? saved;
    try {
      saved = await _storage.read(key: key);
    } catch (_) {
      return;
    }
    final id = int.tryParse(saved ?? '');
    if (id == null || !mounted || _conversationId != null || _messages.isNotEmpty) return;
    await _openConversation(ConversationSummary(id: id, title: ''), restoring: true);
  }

  void _chatChanged(int id, {bool deleted = false, String? title}) {
    if (id != _conversationId) return;
    if (deleted) {
      _openConversation(null);
    } else if (title != null) {
      setState(() => _title = title);
    }
  }

  // ---- Sending ----

  /// The model for a message with pictures: the chosen one if it is Claude (they all see images),
  /// otherwise Claude Sonnet — so "what am I wearing?" in a video call always gets a real look.
  String? get _visionModelId {
    final chosen = _models.where((m) => m.id == _modelId).firstOrNull;
    if (chosen != null && chosen.provider.toLowerCase() == 'anthropic') return chosen.id;
    return (_models.where((m) => m.usable && m.id.startsWith('claude-sonnet')).firstOrNull ??
                _models.where((m) => m.usable && m.provider.toLowerCase() == 'anthropic').firstOrNull)
            ?.id ??
        _modelId;
  }

  /// Sends a message; completes with the finished reply (null if it failed), so voice mode can
  /// wait for the answer before speaking it.
  /// [images]: uploaded photo / video-call frame references sent with the message.
  /// [onText]: the answer so far, each time more of it arrives (voice mode speaks it right away).
  /// [model]: overrides the chosen model (voice calls use a fast one).
  Future<ChatMessage?> _send([
    String? text,
    List<String> images = const [],
    ValueChanged<String>? onText,
    String? model,
  ]) async {
    // Photos added in the message bar go with a typed message (not with voice or a question card).
    final attached = text == null ? [..._attachments] : const <_Attachment>[];
    // An image edit from the Edit screen goes with the words it returned (see _editImage).
    final edit = text != null ? _nextEdit : null;
    _nextEdit = null;
    final photos = [
      for (final a in attached)
        if (a.isPhoto) a,
    ];
    final documents = [
      for (final a in attached)
        if (!a.isPhoto) a,
    ];
    var content = (text ?? _input.text).trim();
    if ((content.isEmpty && attached.isEmpty) || _sending) return null;
    // Only attachments: the server needs words, so ask about them.
    if (content.isEmpty) content = documents.isNotEmpty ? chatStrings.summarizeFile : chatStrings.describeImage;
    var files = const <({String reference, String name})>[];
    final done = Completer<ChatMessage?>();
    final speakReply = _voiceTurn;
    _voiceTurn = false;
    if (_listening) await _speech.stop();
    await _tts.stop();

    final userBubble = ChatMessage(role: 'user', content: content)
      ..localImages.addAll(photos.map((a) => a.bytes))
      ..fileNames.addAll(documents.map((a) => a.name!));
    final replyBubble = ChatMessage(role: 'assistant', content: '');
    setState(() {
      _sending = true;
      _input.clear();
      _attachments.clear();
      _messages.addAll([userBubble, replyBubble]);
    });
    _scrollToEnd();

    try {
      if (_conversationId == null) {
        final created = await _api.createConversation();
        _conversationId = created.id;
        _rememberChat(created.id);
      }
      // Photos and documents have been uploading since they were added; usually they are done by now.
      if (photos.isNotEmpty) images = [...images, ...await Future.wait(photos.map((a) => a.reference))];
      files = [
        for (final (i, reference) in (await Future.wait(documents.map((a) => a.reference))).indexed)
          (reference: reference, name: documents[i].name!),
      ];
    } on ApiException catch (e) {
      _fail(replyBubble, e.message);
      return null;
    }

    _reply = _api
        .sendMessage(
          _conversationId!,
          content,
          model: model ?? (images.isEmpty ? _modelId : _visionModelId),
          webSearch: _webSearch,
          images: images,
          // Only voice mode follows the answer as it streams.
          voiceCall: onText != null,
          edit: edit,
          files: files,
        )
        .listen(
          (event) {
            _apply(event, replyBubble, userBubble: userBubble);
            // Voice mode gets the words only (no file cards or image codes to read out).
            if (onText != null && (event is ReplyDelta || event is ReplyReset)) onText(replyBubble.displayText);
          },
          onError: (Object e) {
            _fail(replyBubble, e is ApiException ? e.message : chatStrings.somethingWrong);
            if (!done.isCompleted) done.complete(replyBubble);
          },
          onDone: () {
            if (!done.isCompleted) done.complete(replyBubble);
            if (!mounted) return;
            setState(() {
              _sending = false;
              if (_title.isEmpty) _title = content;
            });
            // A reminder was just created: start watching for it to fire.
            _updatePolling();
            // The website's tools (scheduled tasks, images…) save their results with the answer: reload once.
            unawaited(_refreshQuietly(force: true));
            if (speakReply && !replyBubble.isError && replyBubble.content.isNotEmpty) _speak(replyBubble.content);
          },
          cancelOnError: true,
        );
    return done.future;
  }

  /// Voice mode (the "Talk" button): a full-screen conversation with the animated orb.
  /// Each turn goes through the normal chat, so it is saved like any other message.
  Future<void> _openVoiceMode() async {
    // Voice calls need an account (the shortcut and "open voice" links land here too).
    if (context.read<AuthState>().isGuest) return;
    if (_listening) await _speech.stop();
    await _tts.stop();
    if (!mounted) return;
    // Calls use the fastest Claude (answers start in about 2 s instead of 4–5 s with Sonnet,
    // and it sees the camera too), unless the user picks another model in the call.
    // Only models that really see the camera are offered in calls (Claude for now; the server decides).
    final callModels = _models.where((m) => m.seesImages).toList();
    if (!callModels.any((m) => m.id == _voiceModelId)) {
      _voiceModelId =
          (callModels.where((m) => m.usable && m.id.startsWith('claude-haiku')).firstOrNull ??
                  callModels.where((m) => m.id == _modelId).firstOrNull ??
                  callModels.where((m) => m.usable).firstOrNull ??
                  _models.where((m) => m.id == _modelId).firstOrNull)
              ?.id;
    }
    // The AI voices (fetched again if they had not arrived yet) and the voice picked last time, kept
    // on this phone — so it never falls back to the phone's robotic voice. First call: an American voice.
    if (_aiVoices.isEmpty) {
      try {
        _aiVoices = await _api.voices();
      } on ApiException {
        // No AI voices on this server: the phone's voice is the only one left.
      }
    }
    if (_aiVoiceId == null && _aiVoices.isNotEmpty) {
      final saved = await _loadVoiceChoice();
      _aiVoiceId =
          (_aiVoices.where((v) => v.id == saved).firstOrNull ??
                  _aiVoices.where((v) => v.description.contains('American')).firstOrNull ??
                  _aiVoices.first)
              .id;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => VoiceModeScreen(
          ask: (text, images, onText) async {
            final reply = await _send(text, images, onText, _voiceModelId);
            if (reply == null) return const VoiceReply.failed(null);
            return reply.isError ? VoiceReply.failed(reply.content) : VoiceReply(reply.displayText);
          },
          upload: (bytes) => imageForAi(bytes).then(_api.uploadImage),
          // Stop listening to an answer: cancel the stream (the server still finishes and saves it).
          cancel: _stop,
          userName: context.read<AuthState>().user?.name ?? '',
          models: callModels.isEmpty ? _models : callModels,
          modelId: _voiceModelId,
          onModelChanged: (id) => _voiceModelId = id,
          onNewChat: () => _openConversation(null),
          voices: _aiVoices,
          voiceId: _aiVoiceId,
          onVoiceChanged: (id) {
            _aiVoiceId = id;
            if (id != null) _saveVoiceChoice(id);
          },
          synthesize: _api.speech,
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
    // The call's own voice took over the shared text-to-speech channel: take it back.
    if (mounted) _bindTts();
  }

  static const _voiceKey = 'garad_call_voice';

  /// The AI voice picked for calls last time, remembered on this phone.
  Future<String?> _loadVoiceChoice() async {
    try {
      return await const FlutterSecureStorage().read(key: _voiceKey);
    } catch (_) {
      return null;
    }
  }

  void _saveVoiceChoice(String id) => const FlutterSecureStorage().write(key: _voiceKey, value: id).catchError((_) {});

  /// Read aloud for answers. flutter_tts has one channel for the whole app and the newest FlutterTts
  /// receives its events, so this is redone after voice mode (which has its own) closes.
  void _bindTts() {
    // When reading aloud ends, the speaker button goes back from "stop" to "read aloud".
    void doneSpeaking() {
      if (mounted && _speaking != null) setState(() => _speaking = null);
    }

    _tts = FlutterTts()
      ..setCompletionHandler(doneSpeaking)
      ..setCancelHandler(doneSpeaking)
      ..setErrorHandler((_) => doneSpeaking());
    // Read aloud in a natural American voice, not the device's default.
    useAmericanVoice(_tts);
  }

  /// Applies one streamed event to the reply bubble (shared by send and regenerate).
  void _apply(ChatEvent event, ChatMessage replyBubble, {ChatMessage? userBubble}) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case UserMessageSaved(:final message):
          userBubble?.id = message.id;
        case ReplyDelta(:final text):
          replyBubble.content += text;
        case ToolStatus():
          replyBubble.activity = event;
        case ReplyReset():
          replyBubble.content = '';
        case ReplyDone(:final message):
          replyBubble
            ..activity = null
            ..id = message.id
            ..content = message.content
            ..modelName = message.modelName;
        case TitleUpdated(:final title):
          _title = title;
        case TaskCreated(:final task):
          replyBubble.tasks.add(task);
        case ReplyFailed(:final message, :final saved):
          replyBubble
            ..id = saved?.id
            ..content = message
            ..status = 'error';
      }
    });
    _scrollToEnd();
  }

  // ---- Answer actions (copy · 👍 · 👎 · read aloud · regenerate · share · ⋯) ----

  /// A new answer to the latest question, replacing [bubble]. On failure the old answer comes back.
  Future<void> _regenerate(ChatMessage bubble) async {
    final chatId = _conversationId;
    final messageId = bubble.id;
    if (_sending || chatId == null || messageId == null) return;
    await _tts.stop();
    final oldContent = bubble.content;
    final oldTasks = [...bubble.tasks];
    final oldModel = bubble.modelName;
    void restore(String error) {
      if (!mounted) return;
      setState(() {
        bubble
          ..content = oldContent
          ..modelName = oldModel
          ..status = 'ok';
        bubble.tasks
          ..clear()
          ..addAll(oldTasks);
        _sending = false;
      });
      _snack(error);
    }

    setState(() {
      _sending = true;
      _speaking = null;
      bubble
        ..content = ''
        ..feedback = null;
      bubble.tasks.clear();
    });
    _reply = _api
        .regenerate(chatId, messageId, model: _modelId)
        .listen(
          (event) {
            if (event is ReplyFailed) {
              restore(event.message);
              return;
            }
            _apply(event, bubble);
          },
          onError: (Object e) => restore(e is ApiException ? e.message : chatStrings.somethingWrong),
          onDone: () {
            if (mounted) setState(() => _sending = false);
          },
          cancelOnError: true,
        );
  }

  void _feedback(ChatMessage bubble, String value) {
    final wasSet = bubble.feedback == value;
    setState(() => bubble.feedback = wasSet ? null : value);
    if (!wasSet) _snack(chatStrings.feedbackThanks);
  }

  /// Reads an answer aloud, or stops if it is the one being read.
  Future<void> _toggleSpeak(ChatMessage bubble) async {
    if (_speaking == bubble) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = null);
      return;
    }
    setState(() => _speaking = bubble);
    await _speak(bubble.displayText);
  }

  Future<void> _shareMessage(ChatMessage bubble) async {
    await SharePlus.instance.share(
      ShareParams(text: bubble.displayText, subject: _title.isEmpty ? 'Garad AI' : _title),
    );
  }

  Future<void> _moreActions(ChatMessage bubble) async {
    final c = Palette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bubble.modelName != null)
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(chatStrings.answeredBy),
                subtitle: Text(bubble.modelName!, style: TextStyle(color: c.muted)),
              ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(chatStrings.selectText),
              onTap: () {
                Navigator.pop(sheet);
                showDialog<void>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    content: SingleChildScrollView(child: SelectableText(bubble.displayText)),
                    actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(chatStrings.cancel))],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(chatStrings.copy),
              onTap: () {
                Navigator.pop(sheet);
                Clipboard.setData(ClipboardData(text: bubble.displayText));
                _snack(chatStrings.copied);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _fail(ChatMessage bubble, String message) {
    if (!mounted) return;
    setState(() {
      bubble
        ..content = message
        ..status = 'error';
      _sending = false;
    });
  }

  /// Stops showing the reply. The server still finishes and saves it.
  void _stop() {
    _reply?.cancel();
    setState(() => _sending = false);
  }

  // ---- Voice ----

  /// Dictation (ChatGPT style): what was in the box before (✕ puts it back), which recording this is,
  /// (late words from an ended recording are ignored).
  String _dictationBefore = '';
  int _dictationSession = 0;

  /// ✕ in the recording bar: stop and forget what was said.
  Future<void> _cancelDictation() async {
    _dictationSession++;
    await _speech.cancel();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _input.text = _dictationBefore;
    });
  }

  /// ↑ in the recording bar: stop and send what was said.
  Future<void> _sendDictation() async {
    _dictationSession++;
    await _speech.stop();
    if (!mounted) return;
    setState(() => _listening = false);
    _send();
  }

  /// [voice]: talk-to-Garad mode (auto-send, answer read aloud). Otherwise dictation into the box.
  Future<void> _listen({required bool voice}) async {
    if (_listening) {
      await _speech.stop();
      return;
    }
    void onStatus(String status) {
      if (mounted && (status == 'done' || status == 'notListening')) setState(() => _listening = false);
    }

    void onError(SpeechRecognitionError _) {
      if (mounted) setState(() => _listening = false);
    }

    if (_speechReady != true) {
      _speechReady = await _speech.initialize(onStatus: onStatus, onError: onError);
    }
    // SpeechToText is one shared object and initialize() only sets these the first time: take them
    // back from voice mode, which uses it too.
    _speech
      ..statusListener = onStatus
      ..errorListener = onError;
    if (_speechReady != true) {
      _snack(chatStrings.micUnavailable);
      return;
    }
    await _tts.stop();

    // Somali recognition for Somali users when the phone has it; otherwise the phone's default.
    String? localeId;
    if (chatStrings.isSomali) {
      final locales = await _speech.locales();
      localeId = locales.where((l) => l.localeId.toLowerCase().startsWith('so')).firstOrNull?.localeId;
    }

    final before = _input.text.trim();
    _dictationBefore = _input.text;
    final session = ++_dictationSession;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        // Ended with ✕ or ↑: words that arrive late are not put back in the box.
        if (!mounted || session != _dictationSession) return;
        final words = result.recognizedWords;
        setState(() => _input.text = voice || before.isEmpty ? words : '$before $words');
        if (voice && result.finalResult && words.trim().isNotEmpty) {
          _voiceTurn = true;
          _send(words);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        // Dictation waits through short pauses like ChatGPT's (■ or ↑ ends it); a voice turn ends sooner.
        pauseFor: Duration(seconds: voice ? 3 : 8),
        listenFor: const Duration(seconds: 60),
      ),
    );
  }

  Future<void> _speak(String markdown) async {
    final plain = markdown
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'[*_`#>|~]'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .trim();
    if (plain.isEmpty) return;
    await _tts.stop();
    await _tts.speak(plain);
  }

  /// The Scheduled screen; [highlightId] opens that task's details (from a chat card's Open button).
  Future<void> _openScheduled({int? highlightId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ScheduledScreen(
          highlightId: highlightId,
          onOpenChat: (id) => _openConversation(ConversationSummary(id: id, title: '')),
        ),
      ),
    );
  }

  void _openLibrary() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => LibraryScreen(
        onOpenChat: (id) => _openConversation(ConversationSummary(id: id, title: '')),
        onNewChat: () => _openConversation(null),
      ),
    ),
  );

  /// Artifacts: the apps and websites Garad built. A change asked for there is sent in that app's chat.
  void _openArtifacts() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ArtifactsScreen(
        onOpenChat: (id) => _openConversation(ConversationSummary(id: id, title: '')),
        onNewChat: () => _openConversation(null),
        onChange: (id, change) async {
          if (_conversationId != id) await _openConversation(ConversationSummary(id: id, title: ''));
          if (mounted && _conversationId == id && !_sending) _send(change);
        },
      ),
    ),
  );

  // ---- Helpers ----

  /// The model pill in the message bar: Claude-style "Select model" (Claude models, then "More models").
  Future<void> _modelMenu() async {
    if (_models.isEmpty) return;
    final picked = await showModelPicker(context, models: _models, selectedId: _modelId);
    if (picked != null && mounted) setState(() => _modelId = picked);
  }

  /// ChatGPT-style editing of an image in the chat: the Edit screen (paint the area, describe the
  /// change, quick actions), then its words are sent with the edit; the new image arrives as the answer.
  Future<void> _editImage(String imageUrl, ImageTool tool) async {
    final request = await runImageTool(context, imageUrl, tool);
    if (request == null || !mounted) return;
    _nextEdit = request.edit;
    await _send(request.instruction);
  }

  /// Adds a photo to the next message and starts uploading it straight away.
  void _attach(Uint8List bytes) {
    if (_attachments.where((a) => a.isPhoto).length >= _maxPhotos) {
      _snack(chatStrings.maxPhotos);
      return;
    }
    // Transparent pictures (e.g. a white logo) go on a contrasting background so the AI can see them.
    final reference = imageForAi(bytes).then(_api.uploadImage);
    reference.ignore(); // an upload error is shown when the message is sent
    setState(() => _attachments.add(_Attachment(bytes, reference)));
    _inputFocus.requestFocus();
  }

  /// Adds a document (PDF, Word, Excel, text…) to the next message and starts uploading it.
  void _attachFile(Uint8List bytes, String name) {
    if (_attachments.where((a) => !a.isPhoto).length >= _maxFiles) {
      _snack(chatStrings.maxFiles);
      return;
    }
    if (bytes.length > _maxFileBytes) {
      _snack(chatStrings.fileTooBig);
      return;
    }
    final reference = _api.uploadFile(bytes, name);
    reference.ignore(); // an upload error is shown when the message is sent
    setState(() => _attachments.add(_Attachment(bytes, reference, name: name)));
    _inputFocus.requestFocus();
  }

  /// ＋ → Files: documents the website can read (a picture picked here is sent as a photo).
  Future<void> _pickFiles() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _fileTypes);
      for (final file in files) {
        final bytes = await file.xFile.readAsBytes();
        if (!mounted) return;
        final extension = (file.extension ?? '').toLowerCase();
        if (const ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(extension)) {
          _attach(bytes);
        } else {
          _attachFile(bytes, file.name);
        }
      }
    } catch (e) {
      // Development builds say why (e.g. the file picker is not loaded until a full restart).
      _snack(kDebugMode ? '${chatStrings.filesUnavailable} ($e)' : chatStrings.filesUnavailable);
    }
  }

  /// What ＋ → Files offers: the documents the website's chat reads, and pictures.
  static const _fileTypes = [
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'json', 'md', 'html', 'xml', //
    'png', 'jpg', 'jpeg', 'webp', 'gif',
  ];
  static const _maxFiles = 5;

  /// The website's limit per file (AIChatProAttachmentController: 15 MB).
  static const _maxFileBytes = 15 * 1024 * 1024;

  /// ＋ → Photos (several at once) or Camera. Pictures are made smaller first: quicker to send and
  /// plenty for the AI to see.
  Future<void> _pickPhotos({required bool camera}) async {
    final room = _maxPhotos - _attachments.length;
    if (room <= 0) {
      _snack(chatStrings.maxPhotos);
      return;
    }
    // Browser: the picker's "camera" is only a file-upload window on a computer — use the webcam in the app.
    if (camera && kIsWeb) {
      final bytes = await takePhotoInApp(context);
      if (bytes != null && mounted) _attach(bytes);
      return;
    }
    try {
      final picker = ImagePicker();
      final files = camera
          ? [?await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85)]
          : await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85, limit: room > 1 ? room : null);
      for (final file in files.take(room)) {
        final bytes = await file.readAsBytes();
        if (mounted) _attach(bytes);
      }
    } catch (_) {
      _snack(camera ? chatStrings.cameraUnavailable : chatStrings.photosUnavailable);
    }
  }

  /// ＋ in the message bar, Claude-style "Add to chat": Camera / Photos / Files, web search, scheduled tasks.
  /// The message box, so the ＋ menu can open just above it.
  final _composerKey = GlobalKey();

  /// ＋ : a floating menu just above the button, ChatGPT style (not a sheet from the bottom).
  Future<void> _plusMenu() async {
    FocusScope.of(context).unfocus(); // the keyboard goes down, like ChatGPT
    final box = _composerKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    final top = box?.localToGlobal(Offset.zero).dy ?? screen.height - 140;
    final left = (box?.localToGlobal(Offset.zero).dx ?? 12) + 4;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: chatStrings.close,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialog, _, _) => StatefulBuilder(
        builder: (dialog, setMenu) {
          final c = Palette.of(dialog);
          final dark = Theme.of(dialog).brightness == Brightness.dark;
          Widget item(IconData icon, String label, VoidCallback onTap, {bool checked = false, bool close = true}) =>
              InkWell(
                onTap: () {
                  if (close) Navigator.pop(dialog);
                  onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: c.text.withValues(alpha: 0.07), shape: BoxShape.circle),
                        child: Icon(icon, size: 19, color: checked ? c.brand : c.text),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(label, style: TextStyle(color: c.text, fontSize: 16)),
                      ),
                      if (checked) Icon(Icons.check, size: 18, color: c.brand),
                    ],
                  ),
                ),
              );

          return Stack(
            children: [
              Positioned(
                left: left,
                bottom: screen.height - top + 8,
                width: 240,
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    // Frosted glass over the chat, as in ChatGPT.
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: (dark ? const Color(0xFF2A2A2A) : Colors.white).withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: c.line),
                          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 8))],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            item(Icons.photo_camera_outlined, chatStrings.camera, () => _pickPhotos(camera: true)),
                            item(Icons.photo_outlined, chatStrings.photos, () => _pickPhotos(camera: false)),
                            item(Icons.attach_file, chatStrings.files, _pickFiles),
                            item(
                              Icons.language,
                              chatStrings.webSearch,
                              () {
                                setState(() => _webSearch = !_webSearch);
                                setMenu(() {});
                              },
                              checked: _webSearch,
                              close: false,
                            ),
                            item(Icons.schedule, chatStrings.scheduled, _openScheduled),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      // Grows from the ＋ button (bottom left).
      transitionBuilder: (dialog, animation, _, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(curve),
            alignment: Alignment(-1 + (left + 20) / screen.width * 2, -1 + (top / screen.height) * 2),
            child: child,
          ),
        );
      },
    );
  }

  void _scrollToEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      jump
          ? _scroll.jumpTo(end)
          : _scroll.animateTo(end, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// A tap on "Talk to Garad" while the app is already open.
  void _checkVoiceRequest(int request) {
    if (request == _handledVoiceRequest) return;
    _handledVoiceRequest = request;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _openConversation(null);
      await _openVoiceMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final user = context.watch<AuthState>().user;
    _checkVoiceRequest(context.watch<AppState>().voiceRequest);
    final model = _models.where((m) => m.id == _modelId).firstOrNull;
    final empty = _messages.isEmpty && !_loading;

    final composer = _Composer(
      key: _composerKey,
      controller: _input,
      focusNode: _inputFocus,
      sending: _sending,
      listening: _listening,
      onSend: () => _send(),
      onStop: _stop,
      onDictate: () => _listen(voice: false),
      onVoice: () {
        if (!_listening) _listen(voice: true);
      },
      onTalk: _openVoiceMode,
      onStopListening: () {
        if (_listening) _speech.stop();
      },
      onCancelDictation: _cancelDictation,
      onSendDictation: _sendDictation,
      onPlus: _plusMenu,
      attachments: _attachments,
      onRemoveAttachment: (i) => setState(() => _attachments.removeAt(i)),
      onPasteImage: _attach,
      // Not logged in: one Claude model, chosen by the server — no model pill, no voice calls.
      modelName: (user?.guest ?? false) ? null : model?.shortName,
      canTalk: !(user?.guest ?? false),
      webSearch: _webSearch,
      onModel: _modelMenu,
    );
    // A round icon button in the corners of the top bar (Claude / ChatGPT style).
    Widget roundButton(IconData icon, String tooltip, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.all(6),
      child: IconButton.filledTonal(
        tooltip: tooltip,
        style: IconButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.text),
        icon: Icon(icon, size: 20),
        onPressed: onTap,
      ),
    );
    final disclaimer = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        chatStrings.disclaimer,
        textAlign: TextAlign.center,
        style: TextStyle(color: c.faint, fontSize: 10.5),
      ),
    );

    return Scaffold(
      backgroundColor: c.background,
      drawer: ChatDrawer(
        currentId: _conversationId,
        onSelect: _openConversation,
        onChanged: _chatChanged,
        onOpenScheduled: () => _openScheduled(),
        onOpenLibrary: _openLibrary,
        onOpenArtifacts: _openArtifacts,
      ),
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        // New chat: Claude-style (round ☰ and 🔔 only). Inside a chat: ☰ · new chat · ⋯
        // (the model is chosen from the pill in the message bar).
        leadingWidth: 60,
        leading: Builder(
          builder: (context) =>
              roundButton(Icons.notes_rounded, chatStrings.menu, () => Scaffold.of(context).openDrawer()),
        ),
        // Chatting without an account: "Log in" at the top, like ChatGPT.
        actions: [
          if (user?.guest ?? false)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: () => context.read<AuthState>().leaveGuest(),
                style: FilledButton.styleFrom(
                  backgroundColor: c.text,
                  foregroundColor: c.background,
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(chatStrings.logIn),
              ),
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          // An app rewritten later in the chat ("make it blue") is its next version, like Claude.
          final appVersions = List.filled(_messages.length, 1);
          final seen = <String, int>{};
          for (var i = 0; i < _messages.length; i++) {
            if (_messages[i].isUser) continue;
            final title = appTitleIn(_messages[i].content);
            if (title != null) appVersions[i] = seen[title] = (seen[title] ?? 0) + 1;
          }
          return SafeArea(
            top: false,
            child: empty
                ? Column(
                    children: [
                      Expanded(
                        child: _Welcome(
                          greeting: chatStrings.greeting(
                            (user?.guest ?? false) ? '' : user?.name ?? '',
                            DateTime.now(),
                          ),
                        ),
                      ),
                      Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), child: composer),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: _messages.length,
                                itemBuilder: (context, i) => _Bubble(
                                  appVersion: appVersions[i],
                                  // Changes asked for in an app's preview are sent as the next message.
                                  onAppChange: _sending ? null : (change) => _send(change),
                                  message: _messages[i],
                                  streaming: _sending && i == _messages.length - 1,
                                  onOpenTask: (task) => _openScheduled(highlightId: task.id),
                                  onOpenReminder: (id) => _openScheduled(highlightId: id),
                                  speaking: _speaking == _messages[i],
                                  onToggleSpeak: () => _toggleSpeak(_messages[i]),
                                  onFeedback: (value) => _feedback(_messages[i], value),
                                  onShare: () => _shareMessage(_messages[i]),
                                  onMore: () => _moreActions(_messages[i]),
                                  // Only the latest answer can be regenerated (as in ChatGPT).
                                  onRegenerate: !_sending && i == _messages.length - 1 && _messages[i].id != null
                                      ? () => _regenerate(_messages[i])
                                      : null,
                                  // A question card can be answered while it is the latest message.
                                  onChoose: !_sending && i == _messages.length - 1 ? (answer) => _send(answer) : null,
                                  onEditImage: _sending ? null : _editImage,
                                  chosen: i + 1 < _messages.length && _messages[i + 1].isUser
                                      ? _messages[i + 1].content
                                      : null,
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                        child: Column(children: [composer, disclaimer]),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// A document as a small card: its type badge (PDF / DOC / XLS / PPT) and name. In the message bar
/// before sending, and above the question after.
class _FileChip extends StatelessWidget {
  const _FileChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final kind = switch (extension) {
      'pdf' => 'pdf',
      'xls' || 'xlsx' || 'csv' => 'spreadsheet',
      'ppt' || 'pptx' => 'presentation',
      _ => 'document',
    };
    return Container(
      width: 190,
      height: 64,
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: c.surfaceStrong,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Transform.scale(scale: 0.85, child: DocumentThumb(kind: kind)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.text, fontSize: 13, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

/// A photo added to the next message, and its upload (started when it was added).
class _Attachment {
  const _Attachment(this.bytes, this.reference, {this.name});

  final Uint8List bytes;
  final Future<String> reference;

  /// A document's file name (report.pdf); null for a photo.
  final String? name;

  bool get isPhoto => name == null;
}

/// The empty new-chat screen, Claude-style: the Garad logo and a greeting, centred.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.greeting});

  final String greeting;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/splash-icon.png', height: 40, semanticLabel: 'Garad AI'),
            const SizedBox(height: 14),
            Text(
              greeting,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'serif',
                fontFamilyFallback: const ['Georgia', 'Times New Roman', 'Noto Serif'],
                fontSize: 26,
                color: c.text,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The message bar, Claude-style: a rounded box with the text on top and, under it,
/// ＋ · model pill (· 🌐 when web search is on) … 🎤 · voice.
/// 🎤 and the round voice button open voice mode (the animated orb); the voice button turns into
/// Send while there is text, and into Stop while Garad is answering.
class _Composer extends StatelessWidget {
  const _Composer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.listening,
    required this.onSend,
    required this.onStop,
    required this.onDictate,
    required this.onVoice,
    required this.onStopListening,
    required this.onPlus,
    required this.onTalk,
    required this.modelName,
    required this.webSearch,
    required this.onModel,
    required this.attachments,
    required this.onRemoveAttachment,
    required this.onPasteImage,
    required this.onCancelDictation,
    required this.onSendDictation,
    this.canTalk = true,
  });

  /// False when not logged in: the round voice-call button becomes a (grey) send button.
  final bool canTalk;

  /// The recording bar while dictating: ✕ cancel, ↑ send (■ is [onStopListening]).
  final VoidCallback onCancelDictation;
  final VoidCallback onSendDictation;

  /// Photos and documents added to the next message (shown above the text, each with ✕).
  final List<_Attachment> attachments;
  final ValueChanged<int> onRemoveAttachment;

  /// An image pasted or inserted from the keyboard (Android).
  final ValueChanged<Uint8List> onPasteImage;

  /// Opens voice mode.
  final VoidCallback onTalk;

  /// The chosen model's short name, shown in the pill (null while the list loads).
  final String? modelName;
  final bool webSearch;
  final VoidCallback onModel;

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool listening;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onDictate;
  final VoidCallback onVoice;
  final VoidCallback onStopListening;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pillColor = dark ? c.surfaceStrong : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: pillColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.line),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachments.isNotEmpty)
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                itemCount: attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (attachments[i].name case final name?)
                      _FileChip(name: name)
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(attachments[i].bytes, width: 64, height: 64, fit: BoxFit.cover),
                      ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Tooltip(
                        message: attachments[i].isPhoto ? chatStrings.removePhoto : chatStrings.removeFile,
                        child: GestureDetector(
                          onTap: () => onRemoveAttachment(i),
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: c.text,
                            child: Icon(Icons.close, size: 13, color: c.background),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          TextField(
            controller: controller,
            focusNode: focusNode,
            // Android: an image pasted from the clipboard or picked in the keyboard is added as a photo.
            contentInsertionConfiguration: ContentInsertionConfiguration(
              allowedMimeTypes: const ['image/png', 'image/jpeg', 'image/webp', 'image/gif'],
              onContentInserted: (content) {
                final data = content.data;
                if (data != null) onPasteImage(data);
              },
            ),
            minLines: 1,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            // While dictating, the words being heard are set apart in the serif font, in italics.
            style: listening
                ? TextStyle(
                    fontFamily: serifFont,
                    fontStyle: FontStyle.italic,
                    fontSize: 17,
                    color: c.text,
                    height: 1.4,
                  )
                : TextStyle(fontSize: 16, color: c.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: listening ? chatStrings.listening : chatStrings.messageHint,
              hintStyle: TextStyle(color: listening ? c.brand : c.faint, fontSize: 16),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            ),
          ),
          // Dictating: ✕ · Listening… · ■ stop · ↑ send (the words appear in the box above).
          if (listening)
            Row(
              children: [
                _Circle(
                  color: c.surfaceStrong,
                  tooltip: chatStrings.cancel,
                  onTap: onCancelDictation,
                  child: Icon(Icons.close, size: 20, color: c.text),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.mic, size: 18, color: c.brand),
                      const SizedBox(width: 6),
                      Text(chatStrings.listening, style: TextStyle(color: c.brand, fontSize: 14.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Circle(
                  color: c.surfaceStrong,
                  tooltip: chatStrings.stop,
                  onTap: onStopListening,
                  child: Icon(Icons.stop_rounded, size: 20, color: c.text),
                ),
                const SizedBox(width: 6),
                _Circle(
                  color: c.brand,
                  tooltip: chatStrings.send,
                  onTap: onSendDictation,
                  child: const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                ),
              ],
            )
          else
            Row(
              children: [
                // ＋ : add to chat (camera, photos, files, web search, scheduled)
                _Circle(
                  color: c.surfaceStrong,
                  tooltip: chatStrings.more,
                  onTap: onPlus,
                  child: Icon(Icons.add, size: 20, color: c.text),
                ),
                const SizedBox(width: 6),
                // The model pill, e.g. "Claude Sonnet 5".
                if (modelName != null)
                  Flexible(
                    child: Material(
                      color: c.surfaceStrong,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: onModel,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          child: Text(
                            modelName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.text, fontSize: 13.5, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (webSearch) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: chatStrings.webSearch,
                    child: Icon(Icons.language, size: 20, color: c.brand),
                  ),
                ],
                const Spacer(),
                // 🎤 dictation: talk, and the words are written in the box (the purple button is a voice call).
                IconButton(
                  tooltip: chatStrings.dictate,
                  onPressed: sending ? null : onDictate,
                  icon: Icon(Icons.mic_none, size: 22, color: c.muted),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    // Photos alone can be sent too.
                    final hasText = (value.text.trim().isNotEmpty || attachments.isNotEmpty) && !listening;
                    if (sending) {
                      return _Circle(
                        color: c.text,
                        tooltip: chatStrings.stop,
                        onTap: onStop,
                        child: Icon(Icons.stop_rounded, size: 20, color: c.background),
                      );
                    }
                    if (hasText) {
                      return _Circle(
                        color: c.brand,
                        tooltip: chatStrings.messageHint,
                        onTap: onSend,
                        child: const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                      );
                    }
                    // Not logged in: no voice calls — a grey send button until something is typed.
                    if (!canTalk) {
                      return _Circle(
                        color: c.surfaceStrong,
                        tooltip: chatStrings.messageHint,
                        onTap: null,
                        child: Icon(Icons.arrow_upward_rounded, size: 20, color: c.faint),
                      );
                    }
                    // A voice conversation with Garad.
                    return _Circle(
                      color: c.brand,
                      tooltip: chatStrings.talk,
                      onTap: onTalk,
                      child: const Icon(Icons.graphic_eq, size: 20, color: Colors.white),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A 38 px round button inside the message bar.
class _Circle extends StatelessWidget {
  const _Circle({required this.color, required this.tooltip, required this.onTap, required this.child});

  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(dimension: 38, child: Center(child: child)),
      ),
    ),
  );
}

/// One small grey icon in the row under an answer; [active] tints it (e.g. a chosen 👍).
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.tooltip, required this.onTap, this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: 18,
      color: active ? c.brand : c.faint,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.streaming,
    required this.onOpenTask,
    required this.onOpenReminder,
    required this.speaking,
    required this.onToggleSpeak,
    required this.onFeedback,
    required this.onShare,
    required this.onMore,
    required this.onRegenerate,
    this.onChoose,
    this.onEditImage,
    this.chosen,
    this.onAppChange,
    this.appVersion = 1,
  });

  /// Sends a change asked for in an app's preview (vibe coding). Null while an answer is coming.
  final ValueChanged<String>? onAppChange;

  /// Which version of its app this answer holds.
  final int appVersion;

  /// Answers this message's question card (only on the latest answer).
  final ValueChanged<String>? onChoose;

  /// Opens the Edit screen for an image in this answer.
  final ImageToolHandler? onEditImage;

  /// What the user answered to this message's question card (their next message).
  final String? chosen;

  final ChatMessage message;
  final bool streaming;
  final ValueChanged<ScheduledTask> onOpenTask;
  final ValueChanged<int?> onOpenReminder;
  final bool speaking;
  final VoidCallback onToggleSpeak;
  final ValueChanged<String> onFeedback;
  final VoidCallback onShare;
  final VoidCallback onMore;

  /// Null hides the button (only the latest answer can be regenerated).
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);

    if (message.isUser) {
      // Photos sent with the question sit above it, Claude-style: the picked pictures right after
      // sending, the server's copies when the chat is reopened.
      final api = context.read<AuthState>().api;
      Widget photo(Widget image) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox.square(dimension: 132, child: image),
      );
      final photos = [
        for (final bytes in message.localImages) photo(Image.memory(bytes, fit: BoxFit.cover)),
        if (message.localImages.isEmpty)
          for (final id in message.imageIds)
            photo(
              FutureBuilder<Uint8List>(
                future: api.photo(id),
                builder: (context, snap) => snap.hasData
                    ? Image.memory(snap.data!, fit: BoxFit.cover)
                    : ColoredBox(
                        color: c.surfaceStrong,
                        child: snap.hasError ? Icon(Icons.broken_image_outlined, color: c.faint) : null,
                      ),
              ),
            ),
      ];
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 12, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (photos.isNotEmpty || message.fileNames.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      ...photos,
                      for (final name in message.fileNames) _FileChip(name: name),
                    ],
                  ),
                ),
              // Only a picture or file sent: no text bubble (the question the app added stays hidden).
              if (message.shownText.isNotEmpty)
                // Claude-app style: a soft rounded bubble, clean sans text, larger with roomy lines.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(color: c.surfaceStrong, borderRadius: BorderRadius.circular(20)),
                  child: SelectableText(
                    message.shownText,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 16.5,
                      height: 1.45,
                      letterSpacing: 0.1,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (message.isError) {
      return Container(
        margin: const EdgeInsets.only(right: 24, bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: c.danger, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message.content, style: TextStyle(color: c.danger)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final task in message.tasks) TaskCard(task: task, onOpen: () => onOpenTask(task)),
          if (Reminder.parse(message.content) case final reminder?) ...[
            // ChatGPT-style: a small "Drink water ›" header, then the reminder as a normal answer.
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onOpenReminder(reminder.taskId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (reminder.failed) ...[
                      Icon(Icons.error_outline, size: 15, color: c.danger),
                      const SizedBox(width: 4),
                    ],
                    Text(reminder.title, style: TextStyle(color: reminder.failed ? c.danger : c.muted, fontSize: 13)),
                    Icon(Icons.chevron_right, size: 17, color: c.faint),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            MarkdownBody(data: reminder.message, selectable: true, styleSheet: serifMarkdown(context)),
          ] else
            AnswerView(
              message: message,
              streaming: streaming,
              onChoose: onChoose,
              chosen: chosen,
              onEditImage: onEditImage,
              onAppChange: onAppChange,
              appVersion: appVersion,
            ),
          if (!streaming && message.displayText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  _ActionIcon(
                    icon: Icons.copy_outlined,
                    tooltip: chatStrings.copy,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.displayText));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(chatStrings.copied)));
                    },
                  ),
                  _ActionIcon(
                    icon: message.feedback == 'up' ? Icons.thumb_up : Icons.thumb_up_outlined,
                    tooltip: chatStrings.goodResponse,
                    active: message.feedback == 'up',
                    onTap: () => onFeedback('up'),
                  ),
                  _ActionIcon(
                    icon: message.feedback == 'down' ? Icons.thumb_down : Icons.thumb_down_outlined,
                    tooltip: chatStrings.badResponse,
                    active: message.feedback == 'down',
                    onTap: () => onFeedback('down'),
                  ),
                  _ActionIcon(
                    icon: speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                    tooltip: speaking ? chatStrings.stop : chatStrings.readAloud,
                    active: speaking,
                    onTap: onToggleSpeak,
                  ),
                  if (onRegenerate != null)
                    _ActionIcon(icon: Icons.refresh, tooltip: chatStrings.regenerate, onTap: onRegenerate!),
                  _ActionIcon(icon: Icons.share_outlined, tooltip: chatStrings.share, onTap: onShare),
                  _ActionIcon(icon: Icons.more_horiz, tooltip: chatStrings.more, onTap: onMore),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
