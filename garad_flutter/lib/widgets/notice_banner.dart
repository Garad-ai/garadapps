import 'package:flutter/material.dart';

import '../theme.dart';

/// A slim notice above the page: an announcement or an available update.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.message,
    required this.onDismiss,
    required this.dismissLabel,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: c.brandSoft,
          border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(message, style: TextStyle(color: c.text, fontSize: 14, height: 1.35))),
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!, style: TextStyle(color: c.brand, fontWeight: FontWeight.w700)),
              ),
            IconButton(
              tooltip: dismissLabel,
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 18, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
