import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/screens/voice_mode_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // No real microphone or voice in tests: the speech plugin reports "not available".
  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async => call.method == 'initialize' ? false : null,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (call) async => 1);
  });

  testWidgets('a full voice turn: hear → ask Garad → speak the answer → listen again', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const ttsChannel = MethodChannel('flutter_tts');
    var listenCalls = 0;
    final spoken = <String>[];
    final asked = <String>[];

    // A phone whose speech recogniser and voice work.
    messenger.setMockMethodCallHandler(sttChannel, (call) async {
      switch (call.method) {
        case 'initialize' || 'hasPermission':
          return true;
        case 'listen':
          listenCalls++;
          return true;
        case 'locales':
          return <String>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    Future<void> fromPhone(MethodChannel channel, String method, Object? args) => messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );

    await tester.pumpWidget(MaterialApp(
      home: VoiceModeScreen(
        ask: (text) async {
          asked.add(text);
          return const VoiceReply('**Salaan!** I am Garad.');
        },
        cancel: () {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(listenCalls, 1, reason: 'starts listening straight away');

    // The user speaks; the recogniser sends a partial, then the final sentence.
    await fromPhone(sttChannel, 'soundLevelChange', 6.0);
    await fromPhone(sttChannel, 'textRecognition',
        '{"alternates":[{"recognizedWords":"hello","confidence":0.9}],"resultType":0}');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('hello'), findsOneWidget, reason: 'shows what it hears');
    await fromPhone(sttChannel, 'textRecognition',
        '{"alternates":[{"recognizedWords":"hello garad","confidence":0.9}],"resultType":2}');
    await tester.pump(const Duration(milliseconds: 100));

    expect(asked, ['hello garad'], reason: 'sends the sentence to Garad');
    expect(spoken, ['Salaan! I am Garad.'], reason: 'speaks the answer without Markdown symbols');
    expect(find.textContaining('I am Garad'), findsOneWidget, reason: 'shows the answer as a caption');

    // The voice finishes speaking → voice mode listens again.
    await fromPhone(ttsChannel, 'speak.onComplete', null);
    await tester.pump(const Duration(milliseconds: 100));
    expect(listenCalls, 2, reason: 'listens again after answering');

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // dispose cleanly
  });

  testWidgets('voice mode shows the animated orb and survives a missing microphone', (tester) async {
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => VoiceModeScreen(
                  ask: (text) async => VoiceReply('Echo: $text'),
                  cancel: () {},
                ),
              ));
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    // Let the orb animate for a second (many frames through the painter).
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(VoiceModeScreen), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);

    // Microphone unavailable: the screen says so instead of hanging.
    expect(find.byIcon(Icons.close), findsOneWidget);

    // ✕ ends voice mode.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(closed, isTrue);
  });
}
