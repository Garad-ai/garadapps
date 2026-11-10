import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/screens/voice_mode_screen.dart';

void main() {
  strayWordTests();
  captionTimingTests();
  TestWidgetsFlutterBinding.ensureInitialized();

  // No real microphone or voice in tests: the speech plugin reports "not available".
  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async => call.method == 'initialize' ? false : null,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (call) async => 1);
    // The AI voices' audio player: its one-time setup is shared by every test in this file.
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (call) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async => null);
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
    Future<void> fromPhone(MethodChannel channel, String method, Object? args) =>
        messenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall(method, args)), (_) {});

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(
          ask: (text, images, onText) async {
            asked.add(text);
            return const VoiceReply('**Salaan!** I am Garad.');
          },
          cancel: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(listenCalls, 1, reason: 'starts listening straight away');

    // The user speaks; the recogniser sends a partial, then the final sentence.
    await fromPhone(sttChannel, 'soundLevelChange', 6.0);
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"hello","confidence":0.9}],"resultType":0}',
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('hello'), findsOneWidget, reason: 'shows what it hears');
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"hello garad","confidence":0.9}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(asked, ['hello garad'], reason: 'sends the sentence to Garad');
    // One sentence at a time, without Markdown symbols; the caption shows the sentence being said.
    expect(spoken, ['Salaan!'], reason: 'speaks the answer without Markdown symbols');
    expect(find.text('Salaan!'), findsOneWidget, reason: 'the caption follows the voice');
    expect(find.textContaining('I am Garad'), findsNothing, reason: 'not ahead of the voice');

    await fromPhone(ttsChannel, 'speak.onComplete', null);
    await tester.pump();
    expect(spoken, ['Salaan!', 'I am Garad.']);
    expect(find.text('I am Garad.'), findsOneWidget, reason: 'the caption moves on with the voice');

    // The voice finishes speaking → voice mode listens again.
    await fromPhone(ttsChannel, 'speak.onComplete', null);
    // Without echo cancellation (Android here) the microphone stays closed while Garad talks, and
    // opens again a moment after, once Garad's voice has died away.
    await tester.pump(const Duration(milliseconds: 100));
    expect(listenCalls, 1, reason: 'not straight away: the end of Garad’s voice is still in the room');
    await tester.pump(const Duration(milliseconds: 400));
    expect(listenCalls, 2, reason: 'listens again after answering');

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2)); // let short retry timers finish
    await tester.pumpWidget(const SizedBox()); // dispose cleanly
  });

  testWidgets('a list answer is spoken and captioned as sentences — no "-" bullets or emojis', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const ttsChannel = MethodChannel('flutter_tts');
    final spoken = <String>[];
    messenger.setMockMethodCallHandler(
      sttChannel,
      (call) async => switch (call.method) {
        'initialize' || 'hasPermission' || 'listen' => true,
        'locales' => <String>[],
        _ => null,
      },
    );
    // A voice that finishes each sentence straight away.
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      if (call.method == 'speak') {
        spoken.add(call.arguments as String);
        Future.microtask(
          () => messenger.handlePlatformMessage(
            ttsChannel.name,
            ttsChannel.codec.encodeMethodCall(const MethodCall('speak.onComplete')),
            (_) {},
          ),
        );
      }
      return 1;
    });
    Future<void> fromPhone(MethodChannel channel, String method, Object? args) =>
        messenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall(method, args)), (_) {});

    // The answer from the screenshot: a written list with dashes and an emoji.
    const answer =
        'Hi! 😊 I can help with:\n- Scheduled jobs, monitoring, AI agents\n'
        '- Building tools — websites, apps, dashboards\n1. Planning, coding, learning\nWhat would you like help with?';
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(ask: (text, images, onText) async => const VoiceReply(answer), cancel: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"hi","confidence":0.9}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 200));

    const expected =
        'Hi! I can help with: Scheduled jobs, monitoring, AI agents. '
        'Building tools — websites, apps, dashboards. Planning, coding, learning. What would you like help with?';
    expect(spoken.join(' '), expected, reason: 'clean sentences, spoken one by one');
    expect(spoken.first, 'Hi!');
    // After the answer the caption keeps the last sentence said — not the whole answer.
    expect(find.text('What would you like help with?'), findsOneWidget);
    expect(find.textContaining('Scheduled jobs'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after a tool restarts the answer it still speaks it — without image codes or links', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const ttsChannel = MethodChannel('flutter_tts');
    final spoken = <String>[];
    messenger.setMockMethodCallHandler(
      sttChannel,
      (call) async => switch (call.method) {
        'initialize' || 'hasPermission' || 'listen' => true,
        'locales' => <String>[],
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    Future<void> fromPhone(MethodChannel channel, String method, Object? args) =>
        messenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall(method, args)), (_) {});

    final answer = Completer<VoiceReply>();
    ValueChanged<String>? stream;
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(
          ask: (text, images, onText) {
            stream = onText;
            return answer.future;
          },
          cancel: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"make a logo for my shop","confidence":0.9}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Before the tool runs, a long first sentence is spoken.
    stream!('Sure, I will design a clean modern logo for your coffee shop right now. ');
    await tester.pump();
    expect(spoken, ['Sure, I will design a clean modern logo for your coffee shop right now.']);
    await fromPhone(ttsChannel, 'speak.onComplete', null);

    // The image tool ran and the server restarted the answer: shorter text, with an image code.
    const finalAnswer =
        '[[GARAD_IMAGE_RESULT:aHR0cHM6Ly9nYXJhZC5haS91cGxvYWRzL2xvZ28ucG5n]]\n\n'
        'Here is your logo. See https://garad.ai/uploads/logo.png for the file.';
    stream!(finalAnswer);
    answer.complete(const VoiceReply(finalAnswer));
    await tester.pump();
    await fromPhone(ttsChannel, 'speak.onComplete', null);
    await tester.pump();

    expect(spoken.skip(1).join(' '), contains('Here is your logo.'), reason: 'the restarted answer is spoken');
    expect(spoken.join(' '), isNot(contains('GARAD_IMAGE_RESULT')), reason: 'image codes are not read out');
    expect(spoken.join(' '), isNot(contains('https://')), reason: 'web addresses are not read out');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AI voice: the answer is made in that voice (not the phone voice)', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const ttsChannel = MethodChannel('flutter_tts');
    final phoneSpoke = <String>[];
    final made = <String>[];
    messenger.setMockMethodCallHandler(
      sttChannel,
      (call) async => switch (call.method) {
        'initialize' || 'hasPermission' || 'listen' => true,
        'locales' => <String>[],
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      if (call.method == 'speak') phoneSpoke.add(call.arguments as String);
      return 1;
    });
    Future<void> fromPhone(MethodChannel channel, String method, Object? args) =>
        messenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall(method, args)), (_) {});

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(
          ask: (text, images, onText) async => const VoiceReply('First sentence here. Second one here.'),
          cancel: () {},
          voiceId: 'amina',
          synthesize: (voice, text) async {
            made.add('$voice: $text');
            return Uint8List.fromList([1, 2, 3]);
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"hello there","confidence":0.9}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 200));

    // The answer is made in Amina's voice (played by the audio player — a device plugin, not checked
    // here); the phone's own voice stays quiet.
    // Sentence by sentence, all requested up front so the next is ready when the current one ends.
    expect(made, ['amina: First sentence here.', 'amina: Second one here.']);
    expect(phoneSpoke, isEmpty);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AI voice failing: asks again in the same voice — never switches to the phone voice', (tester) async {
    var tries = 0;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const ttsChannel = MethodChannel('flutter_tts');
    final phoneSpoke = <String>[];
    messenger.setMockMethodCallHandler(
      sttChannel,
      (call) async => switch (call.method) {
        'initialize' || 'hasPermission' || 'listen' => true,
        'locales' => <String>[],
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      if (call.method == 'speak') phoneSpoke.add(call.arguments as String);
      return 1;
    });
    Future<void> fromPhone(MethodChannel channel, String method, Object? args) =>
        messenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall(method, args)), (_) {});

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(
          ask: (text, images, onText) async => const VoiceReply('The AI voice is down.'),
          cancel: () {},
          voiceId: 'oliver',
          synthesize: (voice, text) async {
            tries++;
            throw Exception('server unreachable');
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"are you there","confidence":0.9}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.pump(const Duration(seconds: 2));
    expect(tries, 3, reason: 'the first try and two more, all in Oliver\'s voice');
    expect(phoneSpoke, isEmpty, reason: 'no robotic phone voice mid-call');
    expect(find.text('The AI voice is down.'), findsWidgets, reason: 'still shown as a caption');

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('speaks each sentence as soon as it arrives, before the answer is finished', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const ttsChannel = MethodChannel('flutter_tts');
    final spoken = <String>[];
    var listenCalls = 0;
    messenger.setMockMethodCallHandler(sttChannel, (call) async {
      if (call.method == 'listen') listenCalls++;
      return switch (call.method) {
        'initialize' || 'hasPermission' || 'listen' => true,
        'locales' => <String>[],
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    Future<void> fromPhone(MethodChannel channel, String method, Object? args) =>
        messenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall(method, args)), (_) {});

    final answer = Completer<VoiceReply>();
    ValueChanged<String>? stream;
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(
          ask: (text, images, onText) {
            stream = onText;
            return answer.future;
          },
          cancel: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"tell me something","confidence":0.9}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The first sentence arrives: it is spoken straight away, the unfinished one waits.
    stream!('Hello there. How are');
    await tester.pump();
    expect(spoken, ['Hello there.']);

    stream!('Hello there. How are you today? I am');
    await fromPhone(ttsChannel, 'speak.onComplete', null);
    await tester.pump();
    expect(spoken, ['Hello there.', 'How are you today?']);

    // The answer ends: the rest is spoken, then it listens again.
    answer.complete(const VoiceReply('Hello there. How are you today? I am Garad.'));
    await tester.pump();
    await fromPhone(ttsChannel, 'speak.onComplete', null);
    await tester.pump();
    expect(spoken, ['Hello there.', 'How are you today?', 'I am Garad.']);
    await fromPhone(ttsChannel, 'speak.onComplete', null);
    await tester.pump(const Duration(milliseconds: 600));
    expect(listenCalls, 2, reason: 'listens again after the whole answer was spoken');

    await tester.pump(const Duration(seconds: 2)); // let short retry timers finish
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no echo cancellation: Garad heard by the mic is never sent as the user', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const ttsChannel = MethodChannel('flutter_tts');
    final asked = <String>[];
    final sttCalls = <String>[];
    messenger.setMockMethodCallHandler(sttChannel, (call) async {
      sttCalls.add(call.method);
      return switch (call.method) {
        'initialize' || 'hasPermission' || 'listen' => true,
        'locales' => <String>[],
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(ttsChannel, (call) async => 1);
    Future<void> fromPhone(MethodChannel channel, String method, Object? args) =>
        messenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall(method, args)), (_) {});

    final answer = Completer<VoiceReply>();
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(
          ask: (text, images, onText) {
            asked.add(text);
            return asked.length == 1 ? answer.future : Completer<VoiceReply>().future;
          },
          cancel: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"say goodbye","confidence":0.9}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 100));
    answer.complete(const VoiceReply('Goodbye, have a wonderful day and see you soon.'));
    await tester.pump();
    sttCalls.clear();

    // While Garad talks, a mangled echo of its voice arrives (what the user saw: "waving head
    // sounds like you're"). It must not become a question.
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"waving head sounds like you\'re","confidence":0.9}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(asked, ['say goodbye'], reason: 'the echo is ignored while Garad speaks');
    expect(sttCalls, isNot(contains('listen')), reason: 'the microphone stays closed while Garad speaks');

    // Garad finishes; listening resumes. A sentence the recogniser is very unsure of is dropped.
    await fromPhone(ttsChannel, 'speak.onComplete', null);
    await tester.pump(const Duration(milliseconds: 500));
    expect(sttCalls, contains('listen'));
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"hmm the fan noise","confidence":0.2}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(asked, ['say goodbye'], reason: 'a very unsure sentence is treated as noise');

    // The recogniser ends that session ("done"); the call starts listening again. A clear sentence
    // still goes through.
    await fromPhone(sttChannel, 'notifyStatus', 'done');
    await tester.pump(const Duration(milliseconds: 500));
    await fromPhone(
      sttChannel,
      'textRecognition',
      '{"alternates":[{"recognizedWords":"what time is it","confidence":0.92}],"resultType":2}',
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(asked, ['say goodbye', 'what time is it']);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('iPhone (echo cancelled): talking over Garad stops it — but its own voice does not', (tester) async {
    // The one setup with reliable echo cancellation: an iPhone speaking with its own voice.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const ttsChannel = MethodChannel('flutter_tts');
    final spoken = <String>[];
    var ttsStops = 0;
    final asked = <String>[];
    messenger.setMockMethodCallHandler(sttChannel, (call) async {
      return switch (call.method) {
        'initialize' || 'hasPermission' || 'listen' => true,
        'locales' => <String>[],
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      if (call.method == 'stop') ttsStops++;
      return 1;
    });
    Future<void> heard(String words) => messenger.handlePlatformMessage(
      sttChannel.name,
      sttChannel.codec.encodeMethodCall(
        MethodCall('textRecognition', '{"alternates":[{"recognizedWords":"$words","confidence":0.9}],"resultType":0}'),
      ),
      (_) {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(
          ask: (text, images, onText) async {
            asked.add(text);
            return const VoiceReply('Mogadishu is the capital of Somalia. It sits on the coast.');
          },
          cancel: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await heard('what is the capital');
    await tester.pump(const Duration(milliseconds: 1200)); // the user stops talking
    expect(asked, ['what is the capital']);
    expect(spoken, isNotEmpty, reason: 'Garad is answering');
    final stopsWhileTalking = ttsStops;

    // The microphone picks up Garad's own words: it keeps talking.
    await heard('Mogadishu is the capital');
    await tester.pump();
    expect(ttsStops, stopsWhileTalking, reason: 'its own voice is not the user cutting in');

    // The user talks over it: Garad stops at once, and the new question is sent.
    await heard('Mogadishu is the capital wait tell me about Hargeisa');
    await tester.pump();
    expect(ttsStops, greaterThan(stopsWhileTalking), reason: 'stops talking when the user speaks');
    await tester.pump(const Duration(milliseconds: 1200));
    expect(asked.last, 'wait tell me about hargeisa');

    await tester.pump(const Duration(seconds: 2)); // let short retry timers finish
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null; // flutter_test requires it reset by the end of the test
  });

  testWidgets('live voice: glow animates, Gemini controls, survives a missing microphone', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VoiceModeScreen(
                      ask: (text, images, onText) async => VoiceReply('Echo: $text'),
                      upload: (bytes) async => '/dashboard/user/ai-chat-pro/attachments/test',
                      cancel: () {},
                    ),
                  ),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // Let the glow animate for a second (many frames through the painter).
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(VoiceModeScreen), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no layout overflow on an iPhone-sized screen');

    // Gemini Live controls: video · share photo · mic · end, and captions in the top bar.
    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    expect(find.byIcon(Icons.closed_caption), findsOneWidget);

    // Captions can be hidden.
    await tester.tap(find.byIcon(Icons.closed_caption));
    await tester.pump();
    expect(find.byIcon(Icons.closed_caption_disabled_outlined), findsOneWidget);

    // Microphone unavailable: the screen stays usable (mic button and ✕ are there).
    expect(find.byIcon(Icons.mic_off).evaluate().length + find.byIcon(Icons.mic_none).evaluate().length, 1);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // ✕ ends voice mode.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(closed, isTrue);
  });
}

void strayWordTests() {
  test('a lone filler word is not a question; real one-word replies are', () {
    for (final noise in ['and', 'And.', ' um ', 'uh', 'the']) {
      expect(isStrayWord(noise), isTrue, reason: noise);
    }
    for (final reply in ['yes', 'no', 'hi', 'haa', 'and then what', 'What am I wearing?']) {
      expect(isStrayWord(reply), isFalse, reason: reply);
    }
  });

  testWidgets('hearing only "and" sends nothing; the next real question goes', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const ttsChannel = MethodChannel('flutter_tts');
    final asked = <String>[];
    messenger.setMockMethodCallHandler(
      sttChannel,
      (call) async => switch (call.method) {
        'initialize' || 'hasPermission' || 'listen' => true,
        'locales' => <String>[],
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(ttsChannel, (call) async => 1);
    Future<void> heard(String words) => messenger.handlePlatformMessage(
      sttChannel.name,
      sttChannel.codec.encodeMethodCall(
        MethodCall('textRecognition', '{"alternates":[{"recognizedWords":"$words","confidence":0.9}],"resultType":2}'),
      ),
      (_) {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(
          ask: (text, images, onText) async {
            asked.add(text);
            return const VoiceReply('A maroon shirt.');
          },
          cancel: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await heard('and');
    await tester.pump(const Duration(seconds: 2));
    expect(asked, isEmpty);

    await heard('what am I wearing');
    await tester.pump(const Duration(milliseconds: 200));
    expect(asked, ['what am i wearing']);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
}

void captionTimingTests() {
  testWidgets('AI voice: the caption appears when the voice starts, not before', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    messenger.setMockMethodCallHandler(
      sttChannel,
      (call) async => switch (call.method) {
        'initialize' || 'hasPermission' || 'listen' => true,
        'locales' => <String>[],
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (call) async => 1);
    final audio = Completer<Uint8List>();

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceModeScreen(
          ask: (text, images, onText) async => const VoiceReply("What's the issue you're working on?"),
          cancel: () {},
          voiceId: 'grace',
          synthesize: (voice, text) => audio.future,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await messenger.handlePlatformMessage(
      sttChannel.name,
      sttChannel.codec.encodeMethodCall(
        const MethodCall(
          'textRecognition',
          '{"alternates":[{"recognizedWords":"help me","confidence":0.9}],"resultType":2}',
        ),
      ),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("What's the issue you're working on?"), findsNothing, reason: 'the voice is not ready yet');

    audio.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text("What's the issue you're working on?"), findsOneWidget, reason: 'shown with the voice');

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
}
