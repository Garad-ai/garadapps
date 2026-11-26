import 'package:flutter/material.dart';

import '../theme.dart';

/// A clean confirmation, Claude-style: a bold title, one or two lines saying what happens, and two
/// equal rounded buttons — Cancel, and the action (red when it deletes). True when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialog) {
      final c = Palette.of(dialog);
      final dark = Theme.of(dialog).brightness == Brightness.dark;
      return Dialog(
        backgroundColor: dark ? c.surfaceStrong : Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: c.text, fontSize: 19, fontWeight: FontWeight.w600, height: 1.3),
                ),
                if (message != null && message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(message, style: TextStyle(color: c.muted, fontSize: 15, height: 1.45)),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.text,
                            side: BorderSide(color: c.line),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(cancelLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: destructive ? c.danger : c.brand,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                          ),
                          child: Text(confirmLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return confirmed ?? false;
}
