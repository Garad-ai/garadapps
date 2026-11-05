import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../app_state.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';
import '../widgets/reminder_card.dart';
import '../widgets/task_card.dart';
import 'chat_drawer.dart';
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
  final _tts = FlutterTts();

  final List<ChatMessage> _messages = [];
  List<ChatModelInfo> _models = [];
  int? _conversationId;
  bool _pinned = false;

  /// The engine chosen in the picker; sent with each message (the server keeps no per-chat model).
  String? _modelId;
  String _title = '';
  bool _loading = false;
  bool _sending = false;
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
    // When reading aloud ends, the speaker button goes back from "stop" to "read aloud".
    void doneSpeaking() {
      if (mounted && _speaking != null) setState(() => _speaking = null);
    }

    _tts.setCompletionHandler(doneSpeaking);
    _tts.setCancelHandler(doneSpeaking);
    _tts.setErrorHandler((_) => doneSpeaking());
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
    try {
      final models = await _api.models();
      if (!mounted) return;
      setState(() {
        _models = models;
        if (_modelId == null || !models.any((m) => m.id == _modelId)) {
          _modelId = (models.where((m) => m.isDefault).firstOrNull ?? models.firstOrNull)?.id;
        }
      });
    } on ApiException {
      // The picker stays hidden; the server uses its default model.
    }
  }

  /// Shows a chat from the menu, or a fresh one when [chat] is null.
  /// [restoring]: reopening the last chat at start-up; if it is gone, quietly start a new chat.
  Future<void> _openConversation(ConversationSummary? chat, {bool restoring = false}) async {
    await _reply?.cancel();
    await _tts.stop();
    setState(() {
      _sending = false;
      _messages.clear();
      _conversationId = chat?.id;
      _title = chat?.title ?? '';
      _pinned = chat?.isPinned ?? false;
      _loading = chat != null;
    });
    _rememberChat(chat?.id);
    if (chat == null) return;
    try {
      final result = await _api.conversation(chat.id);
      if (!mounted || _conversationId != chat.id) return;
      setState(() {
        _messages.addAll(result.messages);
        _title = result.conversation.title;
        _pinned = result.conversation.isPinned;
      });
      _scrollToEnd(jump: true);
      _updatePolling();
    } on ApiException catch (e) {
      if (restoring || e.statusCode == 404) {
        // Deleted (here or on the website) or unreachable: start fresh instead of an empty, broken chat.
        if (mounted && _conversationId == chat.id) {
          setState(() {
            _conversationId = null;
            _title = '';
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

  Future<void> _refreshQuietly() async {
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
      if (result.messages.length != before || statusChanged) {
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

  /// Sends a message; completes with the finished reply (null if it failed), so voice mode can
  /// wait for the answer before speaking it.
  Future<ChatMessage?> _send([String? text]) async {
    final content = (text ?? _input.text).trim();
    if (content.isEmpty || _sending) return null;
    final done = Completer<ChatMessage?>();
    final speakReply = _voiceTurn;
    _voiceTurn = false;
    if (_listening) await _speech.stop();
    await _tts.stop();

    final userBubble = ChatMessage(role: 'user', content: content);
    final replyBubble = ChatMessage(role: 'assistant', content: '');
    setState(() {
      _sending = true;
      _input.clear();
      _messages.addAll([userBubble, replyBubble]);
    });
    _scrollToEnd();

    try {
      if (_conversationId == null) {
        final created = await _api.createConversation();
        _conversationId = created.id;
        _rememberChat(created.id);
      }
    } on ApiException catch (e) {
      _fail(replyBubble, e.message);
      return null;
    }

    _reply = _api
        .sendMessage(_conversationId!, content, model: _modelId)
        .listen(
          (event) => _apply(event, replyBubble, userBubble: userBubble),
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
            if (speakReply && !replyBubble.isError && replyBubble.content.isNotEmpty) _speak(replyBubble.content);
          },
          cancelOnError: true,
        );
    return done.future;
  }

  /// Voice mode (the "Talk" button): a full-screen conversation with the animated orb.
  /// Each turn goes through the normal chat, so it is saved like any other message.
  Future<void> _openVoiceMode() async {
    if (_listening) await _speech.stop();
    await _tts.stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => VoiceModeScreen(
          ask: (text) async {
            final reply = await _send(text);
            if (reply == null) return const VoiceReply.failed(null);
            return reply.isError ? VoiceReply.failed(reply.content) : VoiceReply(reply.displayText);
          },
          // Stop listening to an answer: cancel the stream (the server still finishes and saves it).
          cancel: _stop,
          userName: context.read<AuthState>().user?.name ?? '',
          models: _models,
          modelId: _modelId,
          onModelChanged: (id) => setState(() => _modelId = id),
          onNewChat: () => _openConversation(null),
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
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
        case ReplyDone(:final message):
          replyBubble
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

  Future<void> _pickModel() async {
    final c = Palette.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(chatStrings.chooseModel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            for (final m in _models)
              ListTile(
                title: Text(m.name),
                subtitle: Text(m.description ?? m.provider, style: TextStyle(color: c.muted, fontSize: 12)),
                trailing: m.id == _modelId ? Icon(Icons.check, color: c.brand) : null,
                onTap: () => Navigator.pop(context, m.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _modelId) return;
    setState(() => _modelId = picked);
  }

  // ---- Voice ----

  /// [voice]: talk-to-Garad mode (auto-send, answer read aloud). Otherwise dictation into the box.
  Future<void> _listen({required bool voice}) async {
    if (_listening) {
      await _speech.stop();
      return;
    }
    if (_speechReady != true) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (mounted && (status == 'done' || status == 'notListening')) setState(() => _listening = false);
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    }
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
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
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
        pauseFor: const Duration(seconds: 3),
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

  // ---- Top bar actions ----

  Future<void> _shareChat() async {
    final ok = _messages.where((m) => !m.isError && m.content.isNotEmpty);
    if (ok.isEmpty) return;
    final text = [
      if (_title.isNotEmpty) _title,
      for (final m in ok) '${m.isUser ? '🧑' : '🤖 Garad AI'}:\n${m.content}',
    ].join('\n\n');
    await SharePlus.instance.share(ShareParams(text: text, subject: _title.isEmpty ? 'Garad AI' : _title));
  }

  void _showNotifications() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chatStrings.notifications, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 12),
              Text(chatStrings.noNotifications, style: TextStyle(color: Palette.of(context).muted)),
            ],
          ),
        ),
      ),
    );
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

  // ---- Chat menu (⋮) ----

  Future<void> _chatMenu(String action) async {
    final id = _conversationId;
    switch (action) {
      case 'share':
        await _shareChat();
      case 'rename':
        if (id == null) return;
        final controller = TextEditingController(text: _title);
        final title = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(chatStrings.rename),
            content: TextField(controller: controller, autofocus: true, maxLength: 191),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(chatStrings.cancel)),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(chatStrings.save),
              ),
            ],
          ),
        );
        controller.dispose();
        if (title == null || title.isEmpty || title == _title) return;
        try {
          await _api.updateConversation(id, title: title);
          if (mounted) setState(() => _title = title);
        } on ApiException catch (e) {
          _snack(e.message);
        }
      case 'pin':
        if (id == null) return;
        try {
          await _api.updateConversation(id, pinned: !_pinned);
          if (mounted) setState(() => _pinned = !_pinned);
        } on ApiException catch (e) {
          _snack(e.message);
        }
      case 'delete':
        if (id == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(chatStrings.deleteConfirm),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(chatStrings.cancel)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(chatStrings.delete)),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await _api.deleteConversation(id);
          await _openConversation(null);
        } on ApiException catch (e) {
          _snack(e.message);
        }
    }
  }

  // ---- Helpers ----

  /// ＋ in the message bar: choose the AI model, attach a file (coming soon).
  Future<void> _plusMenu() async {
    final c = Palette.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(chatStrings.attach),
              onTap: () {
                Navigator.pop(sheet);
                _soon();
              },
            ),
            if (_models.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(chatStrings.chooseModel, style: TextStyle(color: c.muted, fontSize: 13)),
              ),
              for (final m in _models)
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(m.name),
                  subtitle: Text(m.description ?? m.provider, style: TextStyle(color: c.muted, fontSize: 12)),
                  trailing: m.id == _modelId ? Icon(Icons.check, color: c.brand) : null,
                  onTap: () => Navigator.pop(sheet, m.id),
                ),
            ],
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _modelId = picked);
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

  void _soon() => _snack(chatStrings.comingSoon);

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
      onPlus: _plusMenu,
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
      ),
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        // New chat: Claude-style (round ☰ and 🔔 only). Inside a chat: ChatGPT-style
        // (☰ · model ▾ · new chat · ⋯).
        titleSpacing: empty ? null : 0,
        leadingWidth: 60,
        leading: Builder(
          builder: (context) =>
              roundButton(Icons.notes_rounded, chatStrings.menu, () => Scaffold.of(context).openDrawer()),
        ),
        title: empty
            ? null
            : InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _models.isEmpty ? null : _pickModel,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          model?.name ?? 'Garad AI',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text),
                        ),
                      ),
                      if (_models.isNotEmpty) Icon(Icons.keyboard_arrow_down, size: 20, color: c.muted),
                    ],
                  ),
                ),
              ),
        actions: empty
            ? [
                roundButton(Icons.notifications_none, chatStrings.notifications, _showNotifications),
                const SizedBox(width: 4),
              ]
            : [
                // ChatGPT-style: new chat and ⋯ grouped in one rounded pill.
                Container(
                  decoration: BoxDecoration(color: c.surfaceStrong, borderRadius: BorderRadius.circular(22)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: chatStrings.newChat,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.edit_square, color: c.text, size: 19),
                        onPressed: () => _openConversation(null),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz, color: c.text, size: 20),
                        style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
                        onSelected: _chatMenu,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'share',
                            child: ListTile(leading: const Icon(Icons.ios_share), title: Text(chatStrings.share)),
                          ),
                          if (_conversationId != null) ...[
                            PopupMenuItem(
                              value: 'rename',
                              child: ListTile(
                                leading: const Icon(Icons.edit_outlined),
                                title: Text(chatStrings.rename),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'pin',
                              child: ListTile(
                                leading: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
                                title: Text(_pinned ? chatStrings.unpin : chatStrings.pin),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(Icons.delete_outline, color: c.danger),
                                title: Text(chatStrings.delete, style: TextStyle(color: c.danger)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
      ),
      body: SafeArea(
        top: false,
        child: empty
            ? Column(
                children: [
                  Expanded(child: _Welcome(greeting: chatStrings.greeting(user?.name ?? '', DateTime.now()))),
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
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    child: Column(children: [composer, disclaimer]),
                  ),
                ],
              ),
      ),
    );
  }
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

/// The message bar, Claude-style: one rounded pill — ＋ · text · 🎤 · Talk.
/// 🎤 and "Talk" both open voice mode (the animated orb).
/// "Talk" turns into Send while there is text, and into Stop while Garad is answering.
class _Composer extends StatelessWidget {
  const _Composer({
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
  });

  /// "Talk": opens voice mode.
  final VoidCallback onTalk;

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
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: pillColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.line),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ＋ : model and attachments
          _Circle(
            color: c.surfaceStrong,
            tooltip: chatStrings.more,
            onTap: onPlus,
            child: Icon(Icons.add, size: 20, color: c.text),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 15.5, color: c.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: listening ? chatStrings.listening : chatStrings.messageHint,
                hintStyle: TextStyle(color: listening ? c.brand : c.faint, fontSize: 15),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          // 🎤 opens voice mode (the animated orb), same as "Talk" — always visible, even with text typed.
          _Circle(
            color: c.surfaceStrong,
            tooltip: chatStrings.voiceMode,
            onTap: sending ? null : onTalk,
            child: Icon(Icons.mic_none, size: 20, color: c.text),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty && !listening;
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
              // "Talk": a voice conversation with Garad.
              return Material(
                color: c.text,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onTalk,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.graphic_eq, size: 18, color: c.background),
                        const SizedBox(width: 6),
                        Text(
                          chatStrings.talk,
                          style: TextStyle(color: c.background, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
  });

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
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 12, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: c.surfaceStrong, borderRadius: BorderRadius.circular(18)),
          child: SelectableText(message.content, style: TextStyle(color: c.text, fontSize: 15)),
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
            MarkdownBody(data: reminder.message, selectable: true),
          ] else if (message.content.isEmpty && streaming && message.tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            MarkdownBody(
              data: message.content,
              selectable: true,
              onTapLink: (text, href, title) {
                final uri = href == null ? null : Uri.tryParse(href);
                if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
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
