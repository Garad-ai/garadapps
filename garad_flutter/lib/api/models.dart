/// Data returned by the Garad backend (garad-api).
library;

import '../widgets/reminder_card.dart';

class GaradUser {
  const GaradUser({required this.id, required this.name, required this.email});

  factory GaradUser.fromJson(Map<String, dynamic> json) =>
      GaradUser(id: json['id'] as int, name: json['name'] as String? ?? '', email: json['email'] as String? ?? '');

  final int id;
  final String name;
  final String email;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

/// An AI engine the website admin has set up ("anthropic", "openai", "gemini"; "demo" locally).
class ChatModelInfo {
  const ChatModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    this.description,
    this.isDefault = false,
  });

  factory ChatModelInfo.fromJson(Map<String, dynamic> json) => ChatModelInfo(
        id: '${json['id']}',
        name: json['name'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        description: json['description'] as String?,
        isDefault: json['is_default'] == true,
      );

  final String id;
  final String name;
  final String provider;
  final String? description;
  final bool isDefault;
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
    return message;
  }

  int? id;
  final String role;
  String content;
  String status;
  String? modelName;

  /// Scheduled tasks the AI created while writing this reply (shown as cards above the text).
  final List<ScheduledTask> tasks = [];

  /// 👍 "up" / 👎 "down" from the user; kept in the app only (the website does not store it either).
  String? feedback;

  bool get isUser => role == 'user';
  bool get isError => status == 'error';

  /// The words to copy, share or read aloud: a fired reminder's message, otherwise the content.
  String get displayText => Reminder.parse(content)?.message ?? content;
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
