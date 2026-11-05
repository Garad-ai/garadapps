import 'package:flutter/material.dart';

import '../theme.dart';

/// Full-screen message with one action: offline, maintenance or a required update.
class BlockingScreen extends StatelessWidget {
  const BlockingScreen({
    super.key,
    required this.title,
    required this.body,
    required this.background,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final Color background;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return ColoredBox(
      color: background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/splash-icon.png', width: 64, height: 64),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Text(body, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 15, height: 1.4)),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(180, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
