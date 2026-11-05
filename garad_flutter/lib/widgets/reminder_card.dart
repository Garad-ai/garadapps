import 'dart:convert';

/// A scheduled task that fired, delivered into chat by the website's scheduler as a
/// ```garad-reminder block (JSON: task_id, title, message, fired_at, failed, …).
/// Shown ChatGPT-style: a small "Title ›" header, then the message as a normal answer.
class Reminder {
  const Reminder({required this.taskId, required this.title, required this.message, required this.failed});

  final int? taskId;
  final String title;
  final String message;
  final bool failed;

  /// The reminder in [content], or null if it is not a ```garad-reminder block.
  static Reminder? parse(String content) {
    final match = RegExp(r'^```garad-reminder\s*\n([\s\S]*?)\n?```\s*$').firstMatch(content.trim());
    if (match == null) return null;
    try {
      final data = jsonDecode(match.group(1)!);
      if (data is! Map<String, dynamic>) return null;
      return Reminder(
        taskId: data['task_id'] as int?,
        title: '${data['title'] ?? ''}',
        message: '${data['message'] ?? ''}',
        failed: data['failed'] == true,
      );
    } on FormatException {
      return null;
    }
  }
}
