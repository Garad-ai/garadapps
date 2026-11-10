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
}
