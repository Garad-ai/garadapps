import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../auth_state.dart';
import '../schedule_strings.dart';
import '../theme.dart';

/// The Scheduled screen, ChatGPT-style: ‹ back · "Scheduled", Active / Paused / Completed tabs,
/// task rows with ⋯, a Recommended list and a "New task" button.
/// Tasks are the website's scheduled tasks; the website's scheduler runs them and posts results into chat.
class ScheduledScreen extends StatefulWidget {
  const ScheduledScreen({super.key, this.highlightId, this.onOpenChat});

  /// A task to open straight away (from a chat's task pill or reminder).
  final int? highlightId;

  /// Opens the chat a task reports into.
  final ValueChanged<int>? onOpenChat;

  @override
  State<ScheduledScreen> createState() => _ScheduledScreenState();
}

class _ScheduledScreenState extends State<ScheduledScreen> {
  static const _tabs = ['active', 'paused', 'completed'];

  String _tab = 'active';
  List<ScheduledTask> _all = [];
  bool _loading = true;
  String? _error;
  bool _openedHighlight = false;

  GaradApi get _api => context.read<AuthState>().api;

  /// Tasks for the selected tab. Failed tasks stay under Active (marked red) so they are noticed.
  List<ScheduledTask> get _visible => _all.where((t) {
    return switch (_tab) {
      'paused' => t.status == 'paused',
      'completed' => t.status == 'completed',
      _ => t.status == 'active' || t.status == 'running' || t.status == 'failed',
    };
  }).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fire anything overdue first, so the statuses are current (no-op where cron runs).
      await _api.runDueTasks();
      final result = await _api.tasks();
      if (!mounted) return;
      setState(() => _all = result.items);
      final id = widget.highlightId;
      if (id != null && !_openedHighlight) {
        _openedHighlight = true;
        final task = result.items.where((t) => t.id == id).firstOrNull;
        if (task != null) {
          setState(
            () => _tab = switch (task.status) {
              'paused' => 'paused',
              'completed' => 'completed',
              _ => 'active',
            },
          );
          WidgetsBinding.instance.addPostFrameCallback((_) => _details(task));
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- Actions ----

  /// "New task" sheet; [prefill] comes from a Recommended row.
  Future<void> _newTask({String prefill = ''}) async {
    final created = await showModalBottomSheet<ScheduledTask>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewTaskSheet(api: _api, prefill: prefill),
    );
    if (created == null || !mounted) return;
    _snack(scheduleStrings.created);
    setState(() => _tab = 'active');
    await _load();
  }

  Future<void> _setStatus(ScheduledTask task, String status) async {
    try {
      await _api.setTaskStatus(task.id, status);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _delete(ScheduledTask task) async {
    final s = scheduleStrings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.deleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteTask(task.id);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _openChat(ScheduledTask task) {
    final chatId = task.sourceChatId;
    if (chatId == null || widget.onOpenChat == null) return;
    Navigator.pop(context);
    widget.onOpenChat!(chatId);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _details(ScheduledTask task) async {
    final c = Palette.of(context);
    final s = scheduleStrings;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_emoji(task), style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${s.statuses[task.status] ?? task.status} · ${_when(task)}',
                style: TextStyle(color: task.status == 'failed' ? c.danger : c.muted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Text(task.instructions, style: TextStyle(color: c.text, fontSize: 14)),
              if (task.lastResult != null && task.lastResult!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  s.lastResult,
                  style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(task.lastResult!, style: TextStyle(color: c.text, fontSize: 13)),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in _actionsFor(task))
                    OutlinedButton.icon(
                      style: action.danger ? OutlinedButton.styleFrom(foregroundColor: c.danger) : null,
                      icon: Icon(action.icon, size: 18),
                      label: Text(action.label),
                      onPressed: () {
                        Navigator.pop(sheet);
                        action.run();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_TaskAction> _actionsFor(ScheduledTask task) {
    final s = scheduleStrings;
    return [
      if (task.status == 'active' || task.status == 'running')
        _TaskAction(Icons.pause, s.pause, () => _setStatus(task, 'paused')),
      if (task.status == 'paused' || (task.status == 'failed' && task.recurring))
        _TaskAction(Icons.play_arrow, s.resume, () => _setStatus(task, 'active')),
      if (task.sourceChatId != null && widget.onOpenChat != null)
        _TaskAction(Icons.chat_bubble_outline, s.openChat, () => _openChat(task)),
      _TaskAction(Icons.delete_outline, s.delete, () => _delete(task), danger: true),
    ];
  }

  // ---- Display helpers ----

  /// The emoji the reminder message starts with ("💧 Time to drink…"), else one by task type.
  static String _emoji(ScheduledTask task) {
    final first = task.instructions.trim().characters.firstOrNull ?? '';
    if (first.isNotEmpty && !RegExp(r'[\p{L}\p{N}\p{P}]', unicode: true).hasMatch(first)) return first;
    return switch (task.taskType) {
      'monitor' => '👀',
      'agent_task' => '✨',
      _ => '⏰',
    };
  }

  /// "Today · 2:59 PM", "Tomorrow · 9:00 AM", "December 4 · 9:00 AM", or "Every day at 3:00 PM".
  static String _when(ScheduledTask task) {
    if (task.recurring) return task.schedule;
    final t = task.status == 'completed' || task.nextRunAt == null ? task.lastRunAt : task.nextRunAt;
    if (t == null) return task.schedule;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final s = scheduleStrings;
    final month = s.months[t.month - 1];
    final date = day == today
        ? s.today
        : day == today.add(const Duration(days: 1))
        ? s.tomorrow
        : '${month[0]}${month.substring(1).toLowerCase()} ${t.day}';
    return '$date · ${clockTime(t)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = scheduleStrings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rowColor = dark ? c.surfaceStrong : Colors.white;
    final visible = _visible;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.text),
            icon: const Icon(Icons.chevron_left),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          s.title,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: c.text),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTask,
        backgroundColor: c.brand,
        foregroundColor: Colors.white,
        label: Text(s.newTask, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
          children: [
            // Active / Paused / Completed
            Row(
              children: [
                for (final tab in _tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Material(
                      color: _tab == tab ? c.surfaceStrong : Colors.transparent,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => setState(() => _tab = tab),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text(
                            s.filters[tab]!,
                            style: TextStyle(
                              color: _tab == tab ? c.text : c.muted,
                              fontWeight: _tab == tab ? FontWeight.w600 : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading && _all.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted),
                  ),
                ),
              )
            else if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(s.empty, style: TextStyle(color: c.faint)),
                ),
              )
            else
              for (final task in visible)
                _Row(
                  color: rowColor,
                  leading: _emoji(task),
                  title: task.title,
                  subtitle: task.status == 'failed' ? '${s.statuses['failed']} · ${_when(task)}' : _when(task),
                  subtitleColor: task.status == 'failed' ? c.danger : null,
                  onTap: () => _details(task),
                  menu: _actionsFor(task),
                ),
            // Recommended
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
              child: Text(
                s.recommended,
                style: TextStyle(color: c.muted, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            for (final (emoji, label, prompt) in s.suggestions)
              _Row(
                color: rowColor,
                leading: emoji,
                title: label,
                onTap: () => _newTask(prefill: prompt),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskAction {
  const _TaskAction(this.icon, this.label, this.run, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback run;
  final bool danger;
}

/// One rounded row: emoji · title (· subtitle) · optional ⋯ menu.
class _Row extends StatelessWidget {
  const _Row({
    required this.color,
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.subtitleColor,
    this.menu,
  });

  final Color color;
  final String leading;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback onTap;
  final List<_TaskAction>? menu;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              subtitle == null ? 12 : 10,
              menu == null ? 14 : 2,
              subtitle == null ? 12 : 10,
            ),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text(leading, style: const TextStyle(fontSize: 19))),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14.5,
                          fontWeight: subtitle == null ? FontWeight.w400 : FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subtitleColor ?? c.muted, fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                if (menu != null)
                  PopupMenuButton<int>(
                    icon: Icon(Icons.more_horiz, color: c.muted),
                    onSelected: (i) => menu![i].run(),
                    itemBuilder: (_) => [
                      for (var i = 0; i < menu!.length; i++)
                        PopupMenuItem(
                          value: i,
                          child: Row(
                            children: [
                              Icon(menu![i].icon, size: 18, color: menu![i].danger ? c.danger : null),
                              const SizedBox(width: 10),
                              Text(menu![i].label, style: TextStyle(color: menu![i].danger ? c.danger : null)),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet: describe a task in your own words; Garad works out the schedule.
class _NewTaskSheet extends StatefulWidget {
  const _NewTaskSheet({required this.api, required this.prefill});

  final GaradApi api;
  final String prefill;

  @override
  State<_NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends State<_NewTaskSheet> {
  late final _text = TextEditingController(text: widget.prefill);
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final text = _text.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final task = await widget.api.createTask(text);
      if (mounted) Navigator.pop(context, task);
    } on ApiException catch (e) {
      // e.g. Garad asks "At what time?" — show it so the user can add the time.
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = scheduleStrings;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.newTask,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            enabled: !_busy,
            decoration: InputDecoration(
              hintText: s.newTaskHint,
              hintStyle: TextStyle(color: c.faint, fontSize: 13.5),
              filled: true,
              fillColor: c.surfaceStrong,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, style: TextStyle(color: c.brand, fontSize: 13.5)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _create,
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(s.create, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
