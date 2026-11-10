/// Data returned by the Garad backend (garad-api).
library;

import 'dart:typed_data';

import '../widgets/reminder_card.dart';

class GaradUser {
  const GaradUser({required this.id, required this.name, required this.email, this.guest = false});

  factory GaradUser.fromJson(Map<String, dynamic> json) => GaradUser(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    guest: json['guest'] == true,
  );

  final int id;
  final String name;
  final String email;

  /// Chatting without an account (ChatGPT style): limited messages a day, no files or images.
  final bool guest;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email, 'guest': guest};
}

/// An AI engine the website admin has set up ("anthropic", "openai", "gemini"; "demo" locally).
class ChatModelInfo {
  const ChatModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    this.description,
    this.isDefault = false,
    this.available = true,
    this.locked = false,
    bool? seesImages,
  }) : seesImages = seesImages ?? provider == 'anthropic';

  factory ChatModelInfo.fromJson(Map<String, dynamic> json) => ChatModelInfo(
    id: '${json['id']}',
    name: json['name'] as String? ?? '',
    provider: json['provider'] as String? ?? '',
    description: json['description'] as String?,
    isDefault: json['is_default'] == true,
    available: json['available'] != false,
    locked: json['locked'] == true,
    seesImages: json['sees_images'] as bool?,
  );

  /// It really sees the camera picture in a video call (the server decides; Claude for now).
  final bool seesImages;

  final String id;
  final String name;
  final String provider;
  final String? description;
  final bool isDefault;

  /// False when the user has no credits left for this model (the website's credit system).
  final bool available;

  /// True when the model needs a higher plan.
  final bool locked;

  bool get usable => available && !locked;

  /// The short name before the website's long marketing text ("Gemini 3.7 Flash Frontier …" → "Gemini 3.7 Flash").
  String get shortName {
    final cut = RegExp(r'\s+(\(|[A-Z][a-z]+,? [a-z])').firstMatch(name);
    return cut == null ? name : name.substring(0, cut.start).trim();
  }
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    this.isPinned = false,
    this.modelId,
    this.modelName,
    this.updatedAt,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final model = json['model'];
    return ConversationSummary(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      isPinned: json['is_pinned'] == true,
      modelId: model is Map && model['id'] != null ? '${model['id']}' : null,
      modelName: model is Map ? model['name'] as String? : null,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '')?.toLocal(),
    );
  }

  final int id;
  final String title;
  final bool isPinned;
  final String? modelId;
  final String? modelName;
  final DateTime? updatedAt;
}

/// An image the user created in a chat (the Library).
class LibraryImage {
  const LibraryImage({
    required this.id,
    required this.url,
    required this.prompt,
    this.chatId,
    this.chatTitle,
    this.createdAt,
  });

  factory LibraryImage.fromJson(Map<String, dynamic> json) => LibraryImage(
    id: '${json['id']}',
    url: json['url'] as String? ?? '',
    prompt: json['prompt'] as String? ?? '',
    chatId: json['chat_id'] as int?,
    chatTitle: json['chat_title'] as String?,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
  );

  final DateTime? createdAt;

  final String id;
  final String url;
  final String prompt;
  final int? chatId;
  final String? chatTitle;
}

/// An edit of an image in the chat (the Edit screen), sent with the instruction as a message.
class ImageEdit {
  const ImageEdit({required this.imageUrl, this.mask, this.size});

  /// The image to change: its address as it appears in the chat.
  final String imageUrl;

  /// The painted area as a PNG: transparent where to change, opaque where to keep. Null = whole image.
  final Uint8List? mask;

  /// A new shape: 1024x1024 (square), 1024x1536 (portrait) or 1536x1024 (landscape).
  final String? size;
}

/// An AI voice for calls, e.g. Amina · "Young woman · East African accent".
class AiVoice {
  const AiVoice({required this.id, required this.name, required this.description});

  factory AiVoice.fromJson(Map<String, dynamic> json) => AiVoice(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
  );

  final String id;
  final String name;
  final String description;
}

/// An app or website the AI built in a chat (Artifacts): its latest version.
/// A picture from the web for one idea in an answer (GET /images).
class WebPhoto {
  const WebPhoto({required this.url, this.thumbnail = '', this.title = '', this.source = '', this.link = ''});

  factory WebPhoto.fromJson(Map<String, dynamic> json) => WebPhoto(
    url: json['url'] as String? ?? '',
    thumbnail: json['thumbnail'] as String? ?? '',
    title: json['title'] as String? ?? '',
    source: json['source'] as String? ?? '',
    link: json['link'] as String? ?? '',
  );

  final String url;

  /// A small copy that loads when the original site refuses ([url] fails).
  final String thumbnail;
  final String title;
  final String source;
  final String link;
}

class BuiltApp {
  const BuiltApp({
    required this.id,
    required this.title,
    required this.react,
    required this.source,
    required this.chatId,
    this.chatTitle = '',
    this.version = 1,
    this.createdAt,
  });

  factory BuiltApp.fromJson(Map<String, dynamic> json) => BuiltApp(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    react: json['kind'] == 'react',
    source: json['source'] as String? ?? '',
    chatId: json['chat_id'] as int,
    chatTitle: json['chat_title'] as String? ?? '',
    version: json['version'] as int? ?? 1,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
  );

  /// The answer it is in.
  final int id;
  final String title;

  /// A React component (else a whole HTML page).
  final bool react;
  final String source;
  final int chatId;
  final String chatTitle;
  final int version;
  final DateTime? createdAt;
}

/// A document the AI created in a chat (PDF, Word, Excel, PowerPoint).
class LibraryFile {
  const LibraryFile({
    required this.id,
    required this.title,
    required this.name,
    required this.kind,
    this.size,
    this.chatId,
    this.createdAt,
    this.content,
    this.excerpt,
  });

  factory LibraryFile.fromJson(Map<String, dynamic> json) => LibraryFile(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    name: json['name'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    size: json['size'] as int?,
    chatId: json['chat_id'] as int?,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
    content: json['content'] as String?,
    excerpt: json['excerpt'] as String?,
  );

  final int id;
  final String title;

  /// The file name, e.g. online-business-plan.pdf
  final String name;

  /// pdf · document · spreadsheet · presentation
  final String kind;
  final int? size;
  final int? chatId;
  final DateTime? createdAt;

  /// The document's text (Markdown), only from the preview call; null for older documents.
  final String? content;

  /// A short excerpt, for older documents without [content].
  final String? excerpt;
}

/// One chat bubble. [content] grows while a reply is streaming in.
class ChatMessage {
  ChatMessage({this.id, required this.role, required this.content, this.status = 'ok', this.modelName});

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final message = ChatMessage(
      id: json['id'] as int?,
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      status: json['status'] as String? ?? 'ok',
      modelName: json['model_name'] as String?,
    );
    // Task cards this answer created (kept when the chat is reopened).
    for (final task in json['tasks'] as List? ?? const []) {
      if (task is Map<String, dynamic>) message.tasks.add(ScheduledTask.fromJson(task));
    }
    message.imageIds.addAll([for (final id in json['images'] as List? ?? const []) '$id']);
    message.fileNames.addAll([for (final name in json['files'] as List? ?? const []) '$name']);
    return message;
  }

  /// Documents sent with this question (PDF, Word, Excel, text…), by name.
  final List<String> fileNames = [];

  /// The words the app sent for the user when they sent only a picture or file (the server needs
  /// some text): not shown in their bubble — they wrote nothing.
  static const _defaultQuestions = {
    "What's in this image?",
    'Maxaa sawirkan ku jira?',
    'Summarize this file.',
    'Ka soo koob faylkan.',
  };

  /// The text to show in the user's bubble ('' when they only sent a picture or file).
  String get shownText =>
      (localImages.isNotEmpty || imageIds.isNotEmpty || fileNames.isNotEmpty) && _defaultQuestions.contains(content.trim())
      ? ''
      : content;

  /// Photos sent with this question: attachment ids from the server (see GaradApi.photo) …
  final List<String> imageIds = [];

  /// … or, right after sending, the pictures themselves (shown before the server's copy exists).
  final List<Uint8List> localImages = [];

  int? id;
  final String role;
  String content;
  String status;
  String? modelName;

  /// Scheduled tasks the AI created while writing this reply (shown as cards above the text).
  final List<ScheduledTask> tasks = [];

  /// What the AI is doing right now while answering (creating an image, a PDF…); null when just writing.
  ToolStatus? activity;

  /// 👍 "up" / 👎 "down" from the user; kept in the app only (the website does not store it either).
  String? feedback;

  bool get isUser => role == 'user';
  bool get isError => status == 'error';

  /// The words to copy, share or read aloud: a fired reminder's message, otherwise the content
  /// without file cards, image markers and question blocks.
  String get displayText {
    final text = Reminder.parse(content)?.message ?? content;
    return text
        .replaceAll(RegExp(r'<div class="garad-tool-result-card[\s\S]*?</div>'), '')
        .replaceAll(RegExp(r'\[\[GARAD_[A-Z_]+:[^\]]*\]\]'), '')
        .replaceAll(RegExp(r'```garad-choices[\s\S]*?```'), '')
        .trim();
  }
}

/// The website's tool progress ("event: tool_status"): e.g. create_pdf · working · "Creating PDF…".
class ToolStatus extends ChatEvent {
  const ToolStatus({required this.tool, required this.state, required this.label});

  final String tool;

  /// working · completed · failed · waiting_for_approval · cancelled
  final String state;
  final String label;

  bool get working => state == 'working';
  bool get isImage => tool.contains('image');
  bool get isDocument => const {'create_pdf', 'create_docx', 'create_xlsx', 'create_presentation'}.contains(tool);
}

/// What arrives while a reply is streaming.
sealed class ChatEvent {
  const ChatEvent();
}

class UserMessageSaved extends ChatEvent {
  const UserMessageSaved(this.message);
  final ChatMessage message;
}

class ReplyDelta extends ChatEvent {
  const ReplyDelta(this.text);
  final String text;
}

class ReplyDone extends ChatEvent {
  const ReplyDone(this.message);
  final ChatMessage message;
}

/// The website's engine restarted the answer (after a tool call): clear what was shown.
class ReplyReset extends ChatEvent {
  const ReplyReset();
}

/// The AI created a scheduled task while answering ("remind me in 1 minute…").
class TaskCreated extends ChatEvent {
  const TaskCreated(this.task);
  final ScheduledTask task;
}

/// A Garad scheduled task (reminder, AI task or monitor), shared with the website's Scheduled page.
class ScheduledTask {
  const ScheduledTask({
    required this.id,
    required this.title,
    required this.instructions,
    required this.taskType,
    required this.status,
    required this.scheduleType,
    required this.schedule,
    required this.timezone,
    this.nextRunAt,
    this.lastRunAt,
    this.lastResult,
    this.sourceChatId,
  });

  factory ScheduledTask.fromJson(Map<String, dynamic> json) => ScheduledTask(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    instructions: json['instructions'] as String? ?? '',
    taskType: json['task_type'] as String? ?? 'reminder',
    status: json['status'] as String? ?? 'active',
    scheduleType: json['schedule_type'] as String? ?? 'one_time',
    schedule: json['schedule'] as String? ?? '',
    timezone: json['timezone'] as String? ?? '',
    nextRunAt: DateTime.tryParse(json['next_run_at'] as String? ?? '')?.toLocal(),
    lastRunAt: DateTime.tryParse(json['last_run_at'] as String? ?? '')?.toLocal(),
    lastResult: json['last_result'] as String?,
    sourceChatId: json['source_chat_id'] as int?,
  );

  final int id;
  final String title;
  final String instructions;

  /// reminder | agent_task | monitor
  final String taskType;

  /// active | paused | running | completed | failed
  final String status;

  /// one_time | recurring
  final String scheduleType;

  /// Readable schedule from the server, e.g. "Every day at 3:00 PM".
  final String schedule;
  final String timezone;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final String? lastResult;
  final int? sourceChatId;

  bool get recurring => scheduleType == 'recurring';
}

/// The AI named the chat (sent after the first answer).
class TitleUpdated extends ChatEvent {
  const TitleUpdated(this.title);
  final String title;
}

class ReplyFailed extends ChatEvent {
  const ReplyFailed(this.message, this.saved);
  final String message;
  final ChatMessage? saved;
}
