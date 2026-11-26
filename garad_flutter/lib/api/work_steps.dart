/// The steps of Claude's document engine while it builds a file (slides, Word, PDF), shown as garad.ai
/// shows them (frontend/src/core/workSteps.ts): while Garad works, one line with the current step
/// ("Running a command 11s ›"); afterwards a summary ("Ran a command, created a file, shared files ›")
/// that opens into the list of steps. The Somali wording is the website's (frontend/src/core/i18n.so.ts).
library;

const _kinds = {'command', 'read', 'view', 'create', 'edit', 'note', 'present', 'file'};

/// A file step still unnamed after this long is writing the document: reading a file takes ~2 seconds.
const _writingAfter = Duration(seconds: 3);

class WorkStep {
  WorkStep({
    required this.id,
    required this.kind,
    required this.running,
    this.file,
    this.detail,
    this.title,
    this.startedAt,
    this.doneAt,
  });

  /// A step from the server (live "work_step" event or a saved message); null when malformed.
  static WorkStep? fromJson(Object? raw, {bool saved = false}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    String? text(String key) => raw[key] is String && (raw[key] as String).isNotEmpty ? raw[key] as String : null;
    final kind = raw['kind'];
    return WorkStep(
      id: id,
      kind: kind is String && _kinds.contains(kind) ? kind : 'command',
      running: !saved && raw['state'] != 'done',
      file: text('file'),
      detail: text('detail'),
      title: text('title'),
    );
  }

  final String id;
  String kind;
  bool running;
  String? file;
  String? detail;
  String? title;
  DateTime? startedAt;
  DateTime? doneAt;
}

/// Adds [step], or updates the step with the same id (the server sends only what changed), keeping
/// the order the steps started in.
void mergeWorkStep(List<WorkStep> steps, WorkStep step, Map<String, dynamic> raw, DateTime now) {
  final index = steps.indexWhere((s) => s.id == step.id);
  if (index == -1) {
    steps.add(step
      ..startedAt = now
      ..doneAt = step.running ? null : now);
    return;
  }
  final current = steps[index];
  if (raw.containsKey('kind')) current.kind = step.kind;
  if (raw.containsKey('state')) current.running = step.running;
  current
    ..file = step.file ?? current.file
    ..detail = step.detail ?? current.detail
    ..title = step.title ?? current.title
    ..startedAt ??= now;
  if (!current.running) current.doneAt ??= now;
}

/// Steps saved with a message are all finished.
List<WorkStep> savedWorkSteps(Object? raw) => [
  if (raw is List)
    for (final item in raw) ?WorkStep.fromJson(item, saved: true),
];

String _t(bool so, String en, String somali) => so ? somali : en;

/// The step's line: "Running a command" while it runs, "Ran a command" once done; a note shows its title.
String workStepTitle(WorkStep step, {required bool somali, DateTime? now}) {
  final running = step.running;
  // Claude's own progress line for the step ("Writing the business plan").
  if (step.title != null && step.kind != 'note' && step.kind != 'present') return step.title!;
  final so = somali;
  switch (step.kind) {
    case 'note':
      return step.title ?? _t(so, 'Thinking', 'Waan ka fikirayaa');
    case 'read':
      return running ? _t(so, 'Reading a file', 'Fayl ayaan akhrinayaa') : _t(so, 'Read a file', 'Fayl ayaan akhriyay');
    case 'file':
      if (!running) return _t(so, 'Read a file', 'Fayl ayaan akhriyay');
      final since = (now ?? DateTime.now()).difference(step.startedAt ?? now ?? DateTime.now());
      return since > _writingAfter
          ? _t(so, 'Creating a file', 'Fayl ayaan samaynayaa')
          : _t(so, 'Reading a file', 'Fayl ayaan akhrinayaa');
    case 'view':
      return running ? _t(so, 'Viewing an image', 'Sawir ayaan eegayaa') : _t(so, 'Viewed an image', 'Sawir ayaan eegay');
    case 'create':
      return running ? _t(so, 'Creating a file', 'Fayl ayaan samaynayaa') : _t(so, 'Created a file', 'Fayl ayaan sameeyay');
    case 'edit':
      return running
          ? _t(so, 'Editing a file', 'Fayl ayaan wax ka beddelayaa')
          : _t(so, 'Edited a file', 'Fayl ayaan wax ka beddelay');
    case 'present':
      return _t(so, 'Presented file', 'Faylka ayaan soo bandhigay');
    default:
      return running ? _t(so, 'Running a command', 'Amar ayaan fulinayaa') : _t(so, 'Ran a command', 'Amar ayaan fuliyay');
  }
}

/// The live line while Garad works: the running step, or "Thinking" between steps. Right after a
/// thinking note ends Claude is writing its next step (the deck's script can take a minute), so it
/// says "Writing" then rather than going back to "Thinking".
String workLiveLine(List<WorkStep> steps, {required bool somali, DateTime? now}) {
  final current = steps.reversed.where((s) => s.running).firstOrNull;
  if (current != null) return workStepTitle(current, somali: somali, now: now);
  final last = steps.lastOrNull;
  return last != null && last.kind == 'note' && last.id.startsWith('think-')
      ? _t(somali, 'Writing', 'Waan qorayaa')
      : _t(somali, 'Thinking', 'Waan ka fikirayaa');
}

/// "Ran 3 commands, read 2 files, created a file, shared files", in the order garad.ai uses.
String workSummary(List<WorkStep> steps, {required bool somali}) {
  final so = somali;
  int count(Set<String> kinds) => steps.where((s) => kinds.contains(s.kind)).length;
  final parts = <String>[];
  void add(int n, String one, String oneSo, String many, String manySo) {
    if (n == 1) parts.add(_t(so, one, oneSo));
    if (n > 1) parts.add(_t(so, many, manySo).replaceAll('{count}', '$n'));
  }

  add(count({'command'}), 'ran a command', 'amar ayaan fuliyay', 'ran {count} commands', '{count} amar ayaan fuliyay');
  add(count({'read', 'view', 'file'}), 'read a file', 'fayl ayaan akhriyay', 'read {count} files', '{count} fayl ayaan akhriyay');
  add(count({'create'}), 'created a file', 'fayl ayaan sameeyay', 'created {count} files', '{count} fayl ayaan sameeyay');
  add(count({'edit'}), 'edited a file', 'fayl ayaan wax ka beddelay', 'edited {count} files', '{count} fayl ayaan wax ka beddelay');
  if (count({'present'}) > 0) parts.add(_t(so, 'shared files', 'faylal ayaan wadaagay'));

  final text = parts.join(', ');
  return text.isEmpty
      ? _t(so, 'Worked on the document', 'Dukumentiga ayaan ka shaqeeyay')
      : text[0].toUpperCase() + text.substring(1);
}

/// "45s", "1m 39s": the time since the reply started, as garad.ai shows it.
String formatElapsed(Duration elapsed) {
  final whole = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  return whole < 60 ? '${whole}s' : '${whole ~/ 60}m ${whole % 60}s';
}
