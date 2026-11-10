import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../chat_strings.dart';
import '../theme.dart';

/// Claude-style chat search: a tall sheet with a rounded search field and ✕, then "Recents"
/// (or the matches while typing). Tapping a chat closes the sheet and opens it via [onSelect].
Future<void> showChatSearch(
  BuildContext context, {
  required GaradApi api,
  required ValueChanged<ConversationSummary> onSelect,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Palette.of(context).background,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.94,
    child: _ChatSearch(api: api, onSelect: onSelect),
  ),
);

class _ChatSearch extends StatefulWidget {
  const _ChatSearch({required this.api, required this.onSelect});

  final GaradApi api;
  final ValueChanged<ConversationSummary> onSelect;

  @override
  State<_ChatSearch> createState() => _ChatSearchState();
}

class _ChatSearchState extends State<_ChatSearch> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<ConversationSummary>? _chats;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Recents straight away from the drawer's last list, then fresh from the server.
    final cached = widget.api.cachedChats;
    if (cached != null) _chats = [...cached.pinned, ...cached.recents];
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    try {
      final result = await widget.api.conversations(search: query);
      if (!mounted || query != _query.text.trim()) return;
      setState(() {
        _chats = result.items;
        _failed = false;
      });
    } on ApiException {
      if (mounted && _chats == null) setState(() => _failed = true);
    }
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
    setState(() {});
  }

  void _open(ConversationSummary chat) {
    Navigator.pop(context);
    widget.onSelect(chat);
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final chats = _chats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: c.surfaceStrong.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    onChanged: _onChanged,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(color: c.text, fontSize: 15.5),
                    decoration: InputDecoration(
                      hintText: chatStrings.searchChats,
                      hintStyle: TextStyle(color: c.faint, fontSize: 15.5),
                      prefixIcon: Icon(Icons.search, size: 19, color: c.faint),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: Colors.transparent,
                shape: CircleBorder(side: BorderSide(color: c.line)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context),
                  child: SizedBox.square(dimension: 42, child: Icon(Icons.close, size: 20, color: c.text)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: chats == null
              ? Center(
                  child: _failed
                      ? TextButton(onPressed: _search, child: Text(chatStrings.retry))
                      : const CircularProgressIndicator(strokeWidth: 2),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (_query.text.trim().isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                        child: Text(chatStrings.recents, style: TextStyle(color: c.muted, fontSize: 13.5)),
                      ),
                    for (final chat in chats)
                      InkWell(
                        onTap: () => _open(chat),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
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
                    if (chats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(chatStrings.noResults, style: TextStyle(color: c.faint, fontSize: 14)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Claude's chat icon: a round speech bubble with a small tail at the bottom left, as an outline.
class ChatBubbleIcon extends StatelessWidget {
  const ChatBubbleIcon({super.key, required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _BubblePainter(color));
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.085
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final center = Offset(s * 0.53, s * 0.47);
    final r = s * 0.40;
    // The circle, open at the bottom left where the tail leaves it (from ~115° to ~150°).
    const gapStart = 2.0; // radians, measured clockwise from 3 o'clock
    const gapEnd = 2.62;
    final path = Path()
      // Clockwise from the gap's far side (~150°) all the way round to its near side (~115°)…
      ..addArc(Rect.fromCircle(center: center, radius: r), gapEnd, 2 * math.pi - (gapEnd - gapStart))
      // …then the tail: out to its tip at the bottom left and back to where the arc began.
      ..lineTo(s * 0.10, s * 0.92)
      ..lineTo(center.dx + r * math.cos(gapEnd), center.dy + r * math.sin(gapEnd));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.color != color;
}
