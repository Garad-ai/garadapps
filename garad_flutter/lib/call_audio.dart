import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's speech recognizer plays a beep every time it starts and stops listening, and a call
/// restarts it every few seconds while the user is quiet — a stream of "connecting… disconnected"
/// tones. During a call the app quiets those sounds while it listens ([quiet]) and gives the sound
/// back the moment Garad speaks ([restore]). MainActivity.kt does the work; it also restores the
/// sound if the app is left or closed mid-call. Nothing happens on other platforms.
abstract final class CallAudio {
  static const channel = MethodChannel('ai.garad.app/call_audio');

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Before listening: silence the recognizer's beeps.
  static Future<void> quiet() => _call('quiet');

  /// Before Garad speaks, when muted or when the call ends: the sound is back to normal.
  static Future<void> restore() => _call('restore');

  static Future<void> _call(String method) async {
    if (!_android) return;
    try {
      await channel.invokeMethod<void>(method);
    } catch (_) {
      // An older build without the native side: beeps stay, the call still works.
    }
  }
}
