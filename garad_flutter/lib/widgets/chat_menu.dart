import 'dart:ui';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../chat_strings.dart';
import '../theme.dart';
import 'chat_search_sheet.dart';

/// Claude-style menu for a chat in the side menu: everything behind blurs, the chat lifts out as a
/// rounded pill where it was ([anchor], its rectangle on screen), and a small rounded card opens
/// under it (or above, near the bottom): Pin · Rename · Delete (red).
/// Returns 'pin', 'rename' or 'delete', or null when dismissed.
Future<String?> showChatMenu(BuildContext context, {required ConversationSummary chat, required Rect anchor}) =>
    showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, _, _) => _ChatMenu(chat: chat, anchor: anchor),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          alignment: Alignment.topLeft,
          child: child,
        ),
      ),
    );

class _ChatMenu extends StatelessWidget {
  const _ChatMenu({required this.chat, required this.anchor});

  final ConversationSummary chat;
  final Rect anchor;

  static const _menuWidth = 230.0;
  static const _menuHeight = 170.0;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? c.surfaceStrong : Colors.white;
    final screen = MediaQuery.sizeOf(context);
    final shadow = [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, 8))];
    // Under the chat, or above it when there is no room at the bottom of the screen.
    final below = anchor.bottom + 8 + _menuHeight < screen.height - 16;
    final left = (anchor.left + 4).clamp(8.0, screen.width - _menuWidth - 8);

    Widget item(String value, IconData icon, String label, {Color? color}) => InkWell(
      onTap: () => Navigator.pop(context, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color ?? c.text),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(color: color ?? c.text, fontSize: 15.5)),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        // Blur everything behind (taps there close the menu: the dialog's barrier).
        Positioned.fill(
          child: IgnorePointer(
            child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: const SizedBox.expand()),
          ),
        ),
        // The pressed chat, lifted out.
        Positioned.fromRect(
          rect: anchor,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14), boxShadow: shadow),
            child: Row(
              children: [
                ChatBubbleIcon(color: c.text),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.text, fontSize: 15.5, decoration: TextDecoration.none),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: left,
          top: below ? anchor.bottom + 8 : null,
          bottom: below ? null : screen.height - anchor.top + 8,
          width: _menuWidth,
          child: Material(
            color: card,
            elevation: 0,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: shadow),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  item(
                    'pin',
                    chat.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    chat.isPinned ? chatStrings.unpin : chatStrings.pin,
                  ),
                  Divider(height: 1, color: c.line),
                  item('rename', Icons.edit_outlined, chatStrings.rename),
                  Divider(height: 1, color: c.line),
                  item('delete', Icons.delete_outline, chatStrings.delete, color: c.danger),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
