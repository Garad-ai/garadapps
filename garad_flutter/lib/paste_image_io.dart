import 'dart:typed_data';

/// Phones and desktops: no page paste event. Returns a function that stops listening.
void Function() listenForPastedImages(void Function(Uint8List bytes) onImage) => () {};
