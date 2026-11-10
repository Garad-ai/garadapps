import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/ai_image.dart';

/// A 100x100 PNG: a [logo]-coloured square in the middle, the rest [around] (transparent by default).
Future<Uint8List> png(Color logo, {Color around = const Color(0x00000000)}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = around..blendMode = BlendMode.src);
  canvas.drawRect(const Rect.fromLTWH(30, 30, 40, 40), Paint()..color = logo);
  final image = await recorder.endRecording().toImage(100, 100);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// The colour of one pixel of a picture.
Future<Color> pixel(Uint8List bytes, int x, int y) async {
  final image = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

void main() {
  testWidgets('a white logo on a transparent background goes on a dark background (it was invisible)', (tester) async {
    await tester.runAsync(() async {
      final out = await imageForAi(await png(Colors.white));
      final corner = await pixel(out, 2, 2);
      expect(corner.a, 1.0, reason: 'no longer see-through');
      expect(corner.r, lessThan(0.2), reason: 'dark behind the white logo');
      final logo = await pixel(out, 50, 50);
      expect(logo.r, greaterThan(0.9), reason: 'the logo stays white');
    });
  });

  testWidgets('a dark logo on a transparent background goes on white', (tester) async {
    await tester.runAsync(() async {
      final out = await imageForAi(await png(Colors.black));
      final corner = await pixel(out, 2, 2);
      expect(corner.a, 1.0);
      expect(corner.r, greaterThan(0.9), reason: 'white behind the dark logo');
    });
  });

  testWidgets('pictures without see-through parts are sent unchanged', (tester) async {
    await tester.runAsync(() async {
      final opaque = await png(Colors.red, around: Colors.blue);
      expect(identical(await imageForAi(opaque), opaque), isTrue, reason: 'PNG with nothing transparent');
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      expect(identical(await imageForAi(jpeg), jpeg), isTrue, reason: 'JPEG has no transparency');
    });
  });
}
