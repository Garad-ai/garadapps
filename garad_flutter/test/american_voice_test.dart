import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:garad_ai/american_voice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('flutter_tts');

  /// A device with [voices]; returns what the app asked for (setVoice / setLanguage).
  Future<List<MethodCall>> choose(List<Map<String, String>> voices) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getVoices') return voices;
      calls.add(call);
      return 1;
    });
    await useAmericanVoice(FlutterTts());
    return calls;
  }

  test('reads aloud in the most natural American voice, not a British or robotic one', () async {
    final calls = await choose([
      {'name': 'Microsoft Libby Online (Natural) - English (United Kingdom)', 'locale': 'en-GB'},
      {'name': 'English United States', 'locale': 'en-US'},
      {'name': 'Google US English', 'locale': 'en-US'},
      {'name': 'eSpeak English', 'locale': 'en-US'},
    ]);
    final chosen = calls.singleWhere((c) => c.method == 'setVoice').arguments as Map;
    expect(chosen['name'], 'Google US English');
  });

  test('no American voice listed: still asks for the American accent', () async {
    final calls = await choose([
      {'name': 'Daniel', 'locale': 'en-GB'},
    ]);
    expect(calls.map((c) => c.method), contains('setLanguage'));
    expect(calls.firstWhere((c) => c.method == 'setLanguage').arguments, 'en-US');
  });

  group('a native American man', () {
    test('Android: Google\'s "Male voice 1 (US)", online — not the female voice it used before', () async {
      final calls = await choose([
        {'name': 'en-us-x-tpf-network', 'locale': 'en-US'},
        {'name': 'en-us-x-tpc-network', 'locale': 'en-US'},
        {'name': 'en-us-x-iom-local', 'locale': 'en-US'},
        {'name': 'en-us-x-tpd-network', 'locale': 'en-US'},
        {'name': 'en-us-x-iom-network', 'locale': 'en-US'},
        {'name': 'en-gb-x-rjs-network', 'locale': 'en-GB'},
      ]);
      expect((calls.singleWhere((c) => c.method == 'setVoice').arguments as Map)['name'], 'en-us-x-iom-network');
    });

    test('iPhone: the best male American voice (enhanced), not Samantha or a novelty voice', () {
      final best = bestAmericanVoice([
        {'name': 'Samantha', 'locale': 'en-US', 'gender': 'female', 'quality': 'default', 'identifier': 'com.apple.voice.compact.en-US.Samantha'},
        {'name': 'Fred', 'locale': 'en-US', 'gender': 'male', 'quality': 'default', 'identifier': 'com.apple.speech.synthesis.voice.Fred'},
        {'name': 'Aaron', 'locale': 'en-US', 'gender': 'male', 'quality': 'default', 'identifier': 'com.apple.voice.compact.en-US.Aaron'},
        {'name': 'Evan (Enhanced)', 'locale': 'en-US', 'gender': 'male', 'quality': 'enhanced', 'identifier': 'com.apple.voice.enhanced.en-US.Evan'},
        {'name': 'Daniel', 'locale': 'en-GB', 'gender': 'male', 'quality': 'enhanced', 'identifier': 'com.apple.voice.enhanced.en-GB.Daniel'},
      ]);
      expect(best?['identifier'], 'com.apple.voice.enhanced.en-US.Evan');
    });

    test('Edge / Windows: a natural male voice (Guy), not Aria', () {
      final best = bestAmericanVoice([
        {'name': 'Microsoft Aria Online (Natural) - English (United States)', 'locale': 'en-US'},
        {'name': 'Microsoft Guy Online (Natural) - English (United States)', 'locale': 'en-US'},
        {'name': 'Microsoft Zira - English (United States)', 'locale': 'en-US'},
        {'name': 'Google US English', 'locale': 'en-US'},
      ]);
      expect(best?['name'], 'Microsoft Guy Online (Natural) - English (United States)');
    });

    test('Somali users still get a Somali voice when the phone has one', () {
      final best = bestAmericanVoice([
        {'name': 'en-us-x-iom-network', 'locale': 'en-US'},
        {'name': 'so-so-x-default', 'locale': 'so-SO'},
      ], somali: true);
      expect(best?['locale'], 'so-SO');
    });
  });
}
