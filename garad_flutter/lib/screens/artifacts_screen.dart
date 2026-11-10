import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';
import '../widgets/answer_view.dart';
import 'app_preview_screen.dart';

enum _Filter { all, websites, apps }

/// Claude-style Artifacts: every app and website Garad built in the user's chats, as a grid of
/// cards (latest version of each). Tap one to run it; ask for a change and it is sent in its chat.
class ArtifactsScreen extends StatefulWidget {
  const ArtifactsScreen({super.key, required this.onOpenChat, required this.onChange, this.onNewChat});

  /// Opens the chat an app was built in.
  final ValueChanged<int> onOpenChat;

  /// Sends a change for an app in its chat (chat id, request).
  final void Function(int chatId, String change) onChange;

  /// "＋ New": start a chat to build something new.
  final VoidCallback? onNewChat;

  @override
  State<ArtifactsScreen> createState() => _ArtifactsScreenState();
}

class _ArtifactsScreenState extends State<ArtifactsScreen> {
  List<BuiltApp>? _apps;
  Object? _error;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final apps = await context.read<AuthState>().api.apps();
      if (mounted) {
        setState(() {
          _apps = apps;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(BuiltApp app) async {
    final change = await openAppPreview(
      context,
      AppPart(source: app.source, react: app.react),
      version: app.version,
      onOpenChat: () => _openChat(app.chatId),
    );
    if (change == null || !mounted) return;
    Navigator.of(context).pop();
    widget.onChange(app.chatId, change);
  }

  void _openChat(int chatId) {
    Navigator.of(context).pop();
    widget.onOpenChat(chatId);
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = chatStrings;
    final apps = [
      for (final app in _apps ?? const <BuiltApp>[])
        if (_filter == _Filter.all || (_filter == _Filter.apps) == app.react) app,
    ];
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: s.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(s.artifacts, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          if (widget.onNewChat != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onNewChat!();
                },
                style: FilledButton.styleFrom(backgroundColor: c.brand, visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.newArtifact),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (filter, label) in [
                  (_Filter.all, s.all),
                  (_Filter.websites, s.websites),
                  (_Filter.apps, s.apps),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == filter,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = filter),
                      selectedColor: c.text,
                      labelStyle: TextStyle(color: _filter == filter ? c.background : c.text),
                      backgroundColor: c.surface,
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _apps == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : TextButton(onPressed: _load, child: Text(s.retry)),
                  )
                : apps.isEmpty
                ? _Empty(onNewChat: widget.onNewChat)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 260,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: apps.length,
                      itemBuilder: (context, i) => _AppTile(app: apps[i], onTap: () => _open(apps[i])),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One app: a small "browser window" in the app's own colour, then its name and chat.
class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.onTap});

  final BuiltApp app;
  final VoidCallback onTap;

  static const _colors = [
    Color(0xFF514CFF),
    Color(0xFF0E9F6E),
    Color(0xFFE8590C),
    Color(0xFF0B7285),
    Color(0xFFC2255C),
    Color(0xFF5F3DC4),
  ];

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final accent = _colors[app.title.codeUnits.fold(0, (a, b) => a + b) % _colors.length];
    final kind = app.react ? chatStrings.appKind : chatStrings.websiteKind;
    return Material(
      color: Theme.of(context).brightness == Brightness.dark ? c.surfaceStrong : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.05)],
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(9, 8, 9, 0),
                      child: Row(
                        children: [
                          for (final dot in [0.5, 0.35, 0.2])
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: dot),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Icon(app.react ? Icons.widgets_outlined : Icons.language, size: 38, color: accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.text, fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    app.version > 1 ? '$kind · ${chatStrings.appVersion(app.version)}' : kind,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  if (app.chatTitle.isNotEmpty)
                    Text(
                      app.chatTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.faint, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.onNewChat});

  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_mosaic_outlined, size: 44, color: c.faint),
            const SizedBox(height: 14),
            Text(
              chatStrings.noArtifacts,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 15, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
