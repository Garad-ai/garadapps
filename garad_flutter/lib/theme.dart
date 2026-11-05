import 'package:flutter/material.dart';

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

  static Palette of(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark ? dark : light;
}

/// Parses a CSS hex colour from the web page (`#rgb` or `#rrggbb`); null if it is not one.
Color? parseCssColor(String value) {
  var hex = value.trim().replaceFirst('#', '');
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(0xFF000000 | parsed);
}
