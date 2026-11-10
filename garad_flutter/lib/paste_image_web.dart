import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Browsers: images in a paste (Ctrl+V / ⌘V), e.g. a screenshot. Returns a function that stops listening.
void Function() listenForPastedImages(void Function(Uint8List bytes) onImage) {
  void onPaste(web.ClipboardEvent event) {
    final files = event.clipboardData?.files;
    if (files == null) return;
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null || !file.type.startsWith('image/')) continue;
      file.arrayBuffer().toDart.then((buffer) => onImage(buffer.toDart.asUint8List()));
    }
  }

  final listener = onPaste.toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}
