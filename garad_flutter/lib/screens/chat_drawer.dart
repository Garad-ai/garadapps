import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';
import '../widgets/chat_menu.dart';
import '../widgets/chat_search_sheet.dart';
import 'settings_screen.dart';

/// The side menu: new chat, search, pinned chats, recent chats and the signed-in user.
/// It is rebuilt each time it opens, so the lists are always fresh.
class ChatDrawer extends StatefulWidget {
  const ChatDrawer({
    super.key,
    required this.currentId,
    required this.onSelect,
    required this.onChanged,
    required this.onOpenScheduled,
    required this.onOpenLibrary,
    required this.onOpenArtifacts,
  });

  /// Opens the Library (images created in chats).
  final VoidCallback onOpenLibrary;

  /// Opens Artifacts (the apps and websites Garad built).
  final VoidCallback onOpenArtifacts;

  /// Opens the Scheduled screen.
  final VoidCallback onOpenScheduled;

  /// The chat on screen, highlighted in the list.
  final int? currentId;

  /// Open a chat, or start a new one (null).
  final ValueChanged<ConversationSummary?> onSelect;

  /// A chat was renamed or deleted (the screen may need to update).
  final void Function(int id, {bool deleted, String? title}) onChanged;

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  List<ConversationSummary> _pinned = [];
  final List<ConversationSummary> _recents = [];
  int? _nextPage;
  bool _loading = true;
  bool _loadingMore = false;
  bool _showAll = false;

  /// Recents shown before "See all…".
  static const _shortList = 12;
  String? _error;

  GaradApi get _api => context.read<AuthState>().api;

  @override
  void initState() {
    super.initState();
    // Show the last list straight away (no spinner), then refresh it.
    final cached = _api.cachedChats;
    if (cached != null) {
      _pinned = List.of(cached.pinned);
      _recents.addAll(cached.recents);
      _nextPage = cached.nextPage;
      _loading = false;
    }
    _load(quiet: cached != null);
  }

  /// [quiet]: the list is already on screen; refresh it without a spinner.
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([_api.conversations(pinnedOnly: true), _api.conversations()]);
      if (!mounted) return;
      setState(() {
        _pinned = results[0].items;
        final pinnedIds = {for (final c in _pinned) c.id};
        // Pinned chats live in their own section.
        _recents
          ..clear()
          ..addAll(results[1].items.where((c) => !pinnedIds.contains(c.id)));
        _nextPage = results[1].nextPage;
        _error = null;
      });
      _api.cachedChats = (pinned: List.of(_pinned), recents: List.of(_recents), nextPage: _nextPage);
    } on ApiException catch (e) {
      // With a list already on screen, keep it rather than replacing it with an error.
      if (mounted && (_recents.isEmpty && _pinned.isEmpty)) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final page = _nextPage;
    if (page == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _api.conversations(page: page);
      if (!mounted) return;
      final pinnedIds = {for (final c in _pinned) c.id};
      setState(() {
        _recents.addAll(result.items.where((c) => !pinnedIds.contains(c.id)));
        _nextPage = result.nextPage;
      });
    } on ApiException {
      // Scrolling again retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// The search button: closes the menu and opens the Claude-style search sheet over the chat.
  void _openSearch() {
    final navigator = Navigator.of(context);
    final api = _api;
    navigator.pop();
    showChatSearch(navigator.context, api: api, onSelect: widget.onSelect);
  }

  void _select(ConversationSummary? chat) {
    Navigator.of(context).pop();
    widget.onSelect(chat);
  }

  /// [row]: the pressed chat row's context — the menu opens right under it.
  Future<void> _actions(ConversationSummary chat, BuildContext row) async {
    final box = row.findRenderObject() as RenderBox?;
    if (box == null) return;
    final action = await showChatMenu(context, chat: chat, anchor: box.localToGlobal(Offset.zero) & box.size);
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case 'pin':
          await _api.updateConversation(chat.id, pinned: !chat.isPinned);
        case 'rename':
          final title = await _askTitle(chat.title);
          if (title == null) return;
          await _api.updateConversation(chat.id, title: title);
          widget.onChanged(chat.id, title: title);
        case 'delete':
          if (!await _confirmDelete()) return;
          await _api.deleteConversation(chat.id);
          widget.onChanged(chat.id, deleted: true);
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<String?> _askTitle(String current) async {
    final controller = TextEditingController(text: current);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(chatStrings.rename),
        content: TextField(controller: controller, autofocus: true, maxLength: 255),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(chatStrings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(chatStrings.save)),
        ],
      ),
    );
    controller.dispose();
    return (title == null || title.isEmpty || title == current) ? null : title;
  }

  Future<bool> _confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(chatStrings.deleteConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(chatStrings.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(chatStrings.delete)),
          ],
        ),
      ) ??
      false;

  /// The avatar at the bottom: Settings (account, appearance, log out).
  void _openSettings() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SettingsScreen(onOpenScheduled: widget.onOpenScheduled),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final user = context.watch<AuthState>().user;

    // Claude-style: "Garad AI" + round search, Library / Scheduled, Pinned, Recents,
    // and at the bottom the account avatar (Settings) and a Garad-purple "＋ New chat" pill.
    return Drawer(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 12, 6),
              child: Row(
                children: [
                  Text(
                    'Garad AI',
                    style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: chatStrings.searchChats,
                    child: Material(
                      color: Colors.transparent,
                      shape: CircleBorder(side: BorderSide(color: c.line)),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _openSearch,
                        child: SizedBox.square(dimension: 40, child: Icon(Icons.search, size: 20, color: c.text)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _NavRow(
              icon: Icons.view_week_outlined,
              label: chatStrings.library,
              onTap: () {
                Navigator.of(context).pop();
                widget.onOpenLibrary();
              },
            ),
            _NavRow(
              icon: Icons.auto_awesome_mosaic_outlined,
              label: chatStrings.artifacts,
              onTap: () {
                Navigator.of(context).pop();
                widget.onOpenArtifacts();
              },
            ),
            _NavRow(
              icon: Icons.schedule,
              label: chatStrings.scheduled,
              onTap: () {
                Navigator.of(context).pop();
                widget.onOpenScheduled();
              },
            ),
            Expanded(child: _lists(c)),
            // Bottom: the account avatar (Settings) and a Garad-purple "＋ New chat" pill.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  Tooltip(
                    message: chatStrings.settings,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _openSettings,
                      child: AccountAvatar(name: user?.name ?? ''),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _select(null),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    icon: const Icon(Icons.add, size: 19),
                    label: Text(chatStrings.newChat, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lists(Palette c) {
    if (_loading && _recents.isEmpty && _pinned.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && _recents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
              TextButton(onPressed: _load, child: Text(chatStrings.retry)),
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (_showAll && n.metrics.extentAfter < 200) _loadMore();
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          if (_pinned.isNotEmpty) ...[
            _SectionHeader(label: chatStrings.pinned),
            for (final chat in _pinned) _chatRow(chat, c),
          ],
          _SectionHeader(label: chatStrings.recents),
          // A short list first, like ChatGPT; "See all…" shows (and keeps loading) the rest.
          for (final chat in (_showAll ? _recents : _recents.take(_shortList))) _chatRow(chat, c),
          if (!_showAll && (_recents.length > _shortList || _nextPage != null))
            InkWell(
              onTap: () => setState(() => _showAll = true),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                child: Text(chatStrings.seeAll, style: TextStyle(color: c.muted, fontSize: 14.5)),
              ),
            ),
          if (_recents.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(chatStrings.noChats, style: TextStyle(color: c.faint, fontSize: 13)),
            ),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
    );
  }

  /// One chat: Claude's round chat icon + title; long-press for Pin / Rename / Delete. Highlighted when open.
  Widget _chatRow(ConversationSummary chat, Palette c) {
    final selected = chat.id == widget.currentId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      // The Builder's context is this row: its position anchors the menu.
      child: Builder(
        builder: (row) => Material(
          color: selected ? c.surfaceStrong : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _select(chat),
            onLongPress: () => _actions(chat, row),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
              child: Row(
                children: [
                  ChatBubbleIcon(color: c.text),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.text, fontSize: 15.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.text),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(color: c.text, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

/// "Pinned" / "Recents": a small grey label, Claude-style.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 14, 6),
    child: Text(label, style: TextStyle(color: Palette.of(context).muted, fontSize: 13.5)),
  );
}
