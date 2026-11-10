import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/call_audio.dart';
import 'package:garad_ai/screens/voice_mode_screen.dart';

/// Android (the test default): the recognizer's beeps are quieted while listening, and the sound
/// is back before Garad speaks and when the call ends.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('quiet while listening, sound back to speak and after the call', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const stt = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const tts = MethodChannel('flutter_tts');
    final log = <String>[];

    messenger.setMockMethodCallHandler(CallAudio.channel, (call) async {
      log.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(stt, (call) async {
      switch (call.method) {
        case 'initialize' || 'hasPermission':
          return true;
        case 'listen':
          log.add('listen');
          return true;
        case 'locales':
          return <String>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(tts, (call) async {
      if (call.method == 'speak') log.add('speak');
      return 1;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (call) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async => null);
    Future<void> fromPhone(MethodChannel channel, String method, Object? args) =>
        messenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall(method, args)), (_) {});

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(ask: (text, images, onText) async => const VoiceReply('Hello there.'), cancel: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(log, ['quiet', 'listen']);

    await fromPhone(stt, 'textRecognition', '{"alternates":[{"recognizedWords":"hi garad","confidence":0.9}],"resultType":2}');
    await tester.pump(const Duration(milliseconds: 100));
    expect(log, ['quiet', 'listen', 'restore', 'speak']);

    await fromPhone(tts, 'speak.onComplete', null);
    await tester.pump(const Duration(milliseconds: 600));
    expect(log.sublist(4), ['quiet', 'listen'], reason: 'listening again is quiet again');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(log.last, 'restore', reason: 'ending the call gives the sound back');
  });
}
