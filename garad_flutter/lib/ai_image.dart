import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A picture as the AI should see it. Transparent parts usually reach the AI as white, so a white
/// logo on a transparent background looks blank to it. A picture with transparency is put on a
/// solid background that contrasts with it — dark behind light content, white behind dark — and
/// sent as PNG. Any other picture is returned as it is.
Future<Uint8List> imageForAi(Uint8List bytes) async {
  if (!_mayHaveTransparency(bytes)) return bytes;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) return bytes;

    // How much is see-through, and how light the visible part is (sampled for speed).
    var transparent = 0, visible = 0, samples = 0;
    var lightness = 0.0;
    final step = ((image.width * image.height) ~/ 40000).clamp(1, 1 << 30) * 4;
    for (var i = 0; i + 3 < pixels.lengthInBytes; i += step) {
      samples++;
      final alpha = pixels.getUint8(i + 3);
      if (alpha < 128) {
        transparent++;
      } else {
        visible++;
        lightness += (0.299 * pixels.getUint8(i) + 0.587 * pixels.getUint8(i + 1) + 0.114 * pixels.getUint8(i + 2)) / 255;
      }
    }
    if (transparent == 0 || samples == 0) return bytes; // nothing see-through after all
    final light = visible > 0 && lightness / visible > 0.6;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    canvas.drawRect(Offset.zero & size, Paint()..color = light ? const Color(0xFF1F1F1F) : const Color(0xFFFFFFFF));
    canvas.drawImage(image, Offset.zero, Paint());
    final flat = await recorder.endRecording().toImage(image.width, image.height);
    final png = await flat.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List() ?? bytes;
  } catch (_) {
    return bytes; // could not read it here: let the server try
  }
}

/// PNG with an alpha channel or a transparent colour, WebP with alpha. (JPEG has no transparency.)
bool _mayHaveTransparency(Uint8List b) {
  final png = b.length > 25 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
  if (png) {
    final colorType = b[25]; // IHDR: 4 = grey + alpha, 6 = RGBA
    if (colorType == 4 || colorType == 6) return true;
    // A tRNS chunk (transparent colour) before the image data.
    for (var i = 33; i + 4 < b.length && i < 4096; i++) {
      if (b[i] == 0x74 && b[i + 1] == 0x52 && b[i + 2] == 0x4E && b[i + 3] == 0x53) return true;
    }
    return false;
  }
  final webp = b.length > 20 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45;
  // VP8X header with the alpha flag.
  return webp && b[12] == 0x56 && b[13] == 0x50 && b[14] == 0x38 && b[15] == 0x58 && (b[20] & 0x10) != 0;
}
