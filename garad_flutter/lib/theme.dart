import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// The serif for answers and documents, like Claude's (bundled Source Serif 4).
const serifFont = 'SourceSerif';

/// Answers and document previews: Claude-style serif text, headings and tables.
/// [document]: the full-page preview (larger headings, more space).
MarkdownStyleSheet serifMarkdown(BuildContext context, {bool document = false}) {
  final c = Palette.of(context);
  final body = TextStyle(fontFamily: serifFont, color: c.text, fontSize: document ? 17 : 16.5, height: 1.55);
  final heading = TextStyle(fontFamily: serifFont, color: c.text, fontWeight: FontWeight.w600, height: 1.3);
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: body,
    listBullet: body,
    tableBody: body.copyWith(fontSize: 15),
    tableHead: body.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    blockquote: body.copyWith(color: c.muted),
    strong: const TextStyle(fontWeight: FontWeight.w600),
    h1: heading.copyWith(fontSize: document ? 28 : 23),
    h2: heading.copyWith(fontSize: document ? 24 : 20.5),
    h3: heading.copyWith(fontSize: document ? 20.5 : 18.5),
    h4: heading.copyWith(fontSize: 17.5),
    h1Padding: EdgeInsets.only(top: document ? 20 : 12, bottom: 2),
    h2Padding: EdgeInsets.only(top: document ? 22 : 12, bottom: 2),
    h3Padding: const EdgeInsets.only(top: 10, bottom: 2),
    blockSpacing: 12,
    tableBorder: TableBorder.all(color: c.line),
    tableCellsPadding: const EdgeInsets.all(8),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: c.line, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12),
  );
}

/// Mirrors Chat Pro's app-mode tokens (Garad_ai frontend/src/index.css, data-shell="app").
class Palette {
  const Palette({
    required this.background,
    required this.surface,
    required this.surfaceStrong,
    required this.text,
    required this.muted,
    required this.faint,
    required this.line,
    required this.brand,
    required this.brandSoft,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceStrong;
  final Color text;
  final Color muted;
  final Color faint;
  final Color line;
  final Color brand;
  final Color brandSoft;
  final Color danger;

  static const light = Palette(
    background: Color(0xFFFAF9F5),
    surface: Color(0xFFF6F6F3),
    surfaceStrong: Color(0xFFECECE8),
    text: Color(0xFF1D2421),
    muted: Color(0xFF69716D),
    faint: Color(0xFF939A96),
    line: Color(0xFFDEDFDA),
    brand: Color(0xFF514CFF),
    brandSoft: Color(0xFFEFEFFF),
    danger: Color(0xFFC62828),
  );

  static const dark = Palette(
    background: Color(0xFF262624),
    surface: Color(0xFF181D1B),
    surfaceStrong: Color(0xFF202622),
    text: Color(0xFFEDF0ED),
    muted: Color(0xFFA1AAA5),
    faint: Color(0xFF7A847F),
    line: Color(0xFF333B37),
    brand: Color(0xFF7773FF),
    brandSoft: Color(0xFF29284B),
    danger: Color(0xFFEF5350),
  );

  /// Follows the app's theme (Settings → Light / Dark / System), which follows the phone by default.
  static Palette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Parses a CSS hex colour from the web page (`#rgb` or `#rrggbb`); null if it is not one.
Color? parseCssColor(String value) {
  var hex = value.trim().replaceFirst('#', '');
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(0xFF000000 | parsed);
}
