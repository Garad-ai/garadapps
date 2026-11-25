import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/screens/voice_mode_screen.dart';

/// Where Garad's circle goes on the screen: the camera picture fills the screen like BoxFit.cover
/// (part of it cut off), and the selfie camera is shown like a mirror.
void main() {
  // A phone camera picture (portrait, 1080 × 1920) on a 400 × 800 screen: it is scaled to 450 × 800,
  // so 25 points are cut off on the left and on the right.
  const picture = Size(1080, 1920);
  const screen = Size(400, 800);

  test('the middle of the picture is the middle of the screen', () {
    expect(pictureToScreen(0.5, 0.5, picture, screen, mirrored: false), const Offset(200, 400));
  });

  test('a spot left of the middle, on the back camera, stays on the left', () {
    // 0.25 of 450 = 112.5, minus the 25 cut off on the left.
    expect(pictureToScreen(0.25, 0.2, picture, screen, mirrored: false), const Offset(87.5, 160));
  });

  test('on the selfie camera (shown like a mirror) the same spot is on the right', () {
    // 0.75 of 450 = 337.5, minus 25.
    expect(pictureToScreen(0.25, 0.2, picture, screen, mirrored: true), const Offset(312.5, 160));
  });

  test('a landscape picture on a portrait screen is cut off at the sides', () {
    // 1920 × 1080 scaled to fill 800 high → 1422.2 wide; the middle third stays visible.
    final p = pictureToScreen(0.5, 0.75, const Size(1920, 1080), screen, mirrored: false);
    expect(p.dx, closeTo(200, 0.01));
    expect(p.dy, closeTo(600, 0.01));
  });

  test('a spot in the part cut off still shows, at the nearest edge', () {
    expect(pictureToScreen(0.0, 0.5, picture, screen, mirrored: false), const Offset(24, 400));
    expect(pictureToScreen(1.0, 1.0, picture, screen, mirrored: false), const Offset(376, 776));
  });
}
