import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';

/// The side menu: new chat, search, pinned chats, recent chats and the signed-in user.
/// It is rebuilt each time it opens, so the lists are always fresh.
class ChatDrawer extends StatefulWidget {
  const ChatDrawer({
    super.key,
    required this.currentId,
    required this.onSelect,
    required this.onChanged,
    required this.onOpenScheduled,
  });

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
  final _search = TextEditingController();
  Timer? _debounce;

  List<ConversationSummary> _pinned = [];
  final List<ConversationSummary> _recents = [];
  int? _nextPage;
  bool _loading = true;
  bool _loadingMore = false;
  bool _pinnedOpen = true;
  bool _recentsOpen = true;
  bool _searchOpen = false;
  bool _showAll = false;

  /// Recents shown before "See all…".
  static const _shortList = 12;
  String? _error;

  GaradApi get _api => context.read<AuthState>().api;
  bool get _searching => _search.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _search.text;
      final results = await Future.wait([
        _searching ? Future.value(null) : _api.conversations(pinnedOnly: true),
        _api.conversations(search: query),
      ]);
      if (!mounted || query != _search.text) return;
      setState(() {
        _pinned = results[0]?.items ?? [];
        final pinnedIds = {for (final c in _pinned) c.id};
        _recents
          ..clear()
          // While searching, show every match together; otherwise pinned chats live in their own section.
          ..addAll(results[1]!.items.where((c) => _searching || !pinnedIds.contains(c.id)));
        _nextPage = results[1]!.nextPage;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final page = _nextPage;
    if (page == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _api.conversations(page: page, search: _search.text);
      if (!mounted) return;
      final pinnedIds = {for (final c in _pinned) c.id};
      setState(() {
        _recents.addAll(result.items.where((c) => _searching || !pinnedIds.contains(c.id)));
        _nextPage = result.nextPage;
      });
    } on ApiException {
      // Scrolling again retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
    setState(() {});
  }

  void _select(ConversationSummary? chat) {
    Navigator.of(context).pop();
    widget.onSelect(chat);
  }

  void _soon() => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(chatStrings.comingSoon)));

  Future<void> _actions(ConversationSummary chat) async {
    final c = Palette.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                chat.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: Icon(chat.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(chat.isPinned ? chatStrings.unpin : chatStrings.pin),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(chatStrings.rename),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.danger),
              title: Text(chatStrings.delete, style: TextStyle(color: c.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _account() async {
    final auth = context.read<AuthState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(auth.user?.name ?? ''),
        content: Text('${auth.user?.email ?? ''}\n\n${chatStrings.logoutConfirm}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(chatStrings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(chatStrings.logout)),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop();
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);

    // ChatGPT-style: title + search, Library / Scheduled, Pinned, Recents (See all…),
    // and a "Chat" button with ⚙ at the bottom.
    return Drawer(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 10, 4),
              child: _searchOpen
                  ? TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: _onSearch,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: chatStrings.searchChats,
                        hintStyle: TextStyle(color: c.faint, fontSize: 15),
                        prefixIcon: Icon(Icons.search, size: 20, color: c.faint),
                        prefixIconConstraints: const BoxConstraints(minWidth: 32),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() => _searchOpen = false);
                            _load();
                          },
                        ),
                        border: InputBorder.none,
                      ),
                    )
                  : Row(
                      children: [
                        Text(
                          'Garad AI',
                          style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton.filledTonal(
                          tooltip: chatStrings.searchChats,
                          style: IconButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.text),
                          icon: const Icon(Icons.search, size: 20),
                          onPressed: () => setState(() => _searchOpen = true),
                        ),
                      ],
                    ),
            ),
            if (!_searching) ...[
              const SizedBox(height: 4),
              _NavRow(icon: Icons.view_week_outlined, label: chatStrings.library, onTap: _soon),
              _NavRow(
                icon: Icons.schedule,
                label: chatStrings.scheduled,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onOpenScheduled();
                },
              ),
            ],
            const SizedBox(height: 6),
            Expanded(child: _lists(c)),
            // Bottom: blue "Chat" (new chat) and ⚙ (account).
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => _select(null),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    ),
                    icon: const Icon(Icons.edit_square, size: 18),
                    label: Text(chatStrings.tabChat, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: chatStrings.settings,
                    style: IconButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.text),
                    icon: const Icon(Icons.settings_outlined, size: 21),
                    onPressed: _account,
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
        if ((_showAll || _searching) && n.metrics.extentAfter < 200) _loadMore();
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          if (!_searching && _pinned.isNotEmpty) ...[
            _SectionHeader(
              label: chatStrings.pinned,
              open: _pinnedOpen,
              onTap: () => setState(() => _pinnedOpen = !_pinnedOpen),
            ),
            if (_pinnedOpen)
              for (final chat in _pinned) _chatRow(chat, c, pinned: true),
          ],
          if (!_searching)
            _SectionHeader(
              label: chatStrings.recents,
              open: _recentsOpen,
              onTap: () => setState(() => _recentsOpen = !_recentsOpen),
            ),
          if (_searching || _recentsOpen) ...[
            // A short list first, like ChatGPT; "See all…" shows (and keeps loading) the rest.
            for (final chat in (_searching || _showAll ? _recents : _recents.take(_shortList))) _chatRow(chat, c),
            if (!_searching && !_showAll && (_recents.length > _shortList || _nextPage != null))
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
                child: Text(
                  _searching ? chatStrings.noResults : chatStrings.noChats,
                  style: TextStyle(color: c.faint, fontSize: 13),
                ),
              ),
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
          ],
        ],
      ),
    );
  }

  /// One chat: title only (long-press for pin / rename / delete), highlighted when open.
  Widget _chatRow(ConversationSummary chat, Palette c, {bool pinned = false}) {
    final selected = chat.id == widget.currentId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? c.surfaceStrong : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _select(chat),
          onLongPress: () => _actions(chat),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                if (pinned) ...[Icon(Icons.chat_bubble_outline, size: 17, color: c.text), const SizedBox(width: 12)],
                Expanded(
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.text, fontSize: 15),
                  ),
                ),
              ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.open, required this.onTap});

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 6),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(color: c.muted, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Icon(open ? Icons.expand_more : Icons.chevron_right, size: 16, color: c.faint),
          ],
        ),
      ),
    );
  }
}
