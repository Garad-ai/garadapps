import 'dart:ui';

import 'package:web/web.dart' as web;

String? _last;

void setBrowserColor(Color color) {
  final argb = color.toARGB32();
  final css = '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  if (css == _last) return;
  _last = css;
  web.document.documentElement?.setAttribute('style', 'background-color: $css');
  web.document.body?.style.backgroundColor = css;
  var meta = web.document.querySelector('meta[name="theme-color"]');
  if (meta == null) {
    meta = web.document.createElement('meta')..setAttribute('name', 'theme-color');
    web.document.head?.append(meta);
  }
  meta.setAttribute('content', css);
}
