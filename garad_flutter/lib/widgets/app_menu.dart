import 'package:flutter/material.dart';

import '../remote_config.dart';
import '../strings.dart';
import '../theme.dart';

/// Native bottom sheet opened from "Garad app" in the Chat Pro sidebar.
///
/// [updateNote] is a notifier so "Check for updates" can show "You have the latest version"
/// while the sheet is open.
Future<void> showAppMenu(
  BuildContext context, {
  required AppConfig? config,
  required String version,
  required Color background,
  required ValueNotifier<String?> updateNote,
  required VoidCallback onTalk,
  required VoidCallback? onAgent,
  required void Function(String url) onOpenLink,
  required VoidCallback onCheckUpdates,
}) {
  final c = Palette.of(context);

  Widget row(BuildContext sheetContext, String label, VoidCallback onTap, {bool accent = false}) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      minTileHeight: 50,
      title: Text(
        label,
        style: TextStyle(
          color: accent ? c.brand : c.text,
          fontSize: 16,
          fontWeight: accent ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: c.line, width: 0.5),
    ),
    builder: (sheetContext) {
      void closeThen(VoidCallback action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Semantics(
                header: true,
                child: Text(
                  strings.menuTitle,
                  style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  row(sheetContext, strings.talkToGarad, () => closeThen(onTalk), accent: true),
                  if (onAgent != null) row(sheetContext, strings.agentMenu, () => closeThen(onAgent)),
                  for (final link in config?.links ?? const <AppLink>[])
                    row(sheetContext, link.label, () => closeThen(() => onOpenLink(link.url))),
                  row(sheetContext, strings.checkForUpdates, onCheckUpdates),
                ],
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: updateNote,
              builder: (_, note, _) => note == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(note, style: TextStyle(color: c.muted, fontSize: 13)),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text('${strings.version} $version', style: TextStyle(color: c.faint, fontSize: 12)),
            ),
          ],
        ),
      );
    },
  );
}
