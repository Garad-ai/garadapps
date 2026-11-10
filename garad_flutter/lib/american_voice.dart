import 'package:flutter_tts/flutter_tts.dart';

import 'chat_strings.dart';

/// Makes [tts] speak with the most natural American English voice the phone or browser has
/// (Google US English, Samantha, "Natural"/"Neural" voices…) instead of the robotic or British
/// default. Somali users get a Somali voice when the device has one. Used by Read aloud and calls.
Future<void> useAmericanVoice(FlutterTts tts) async {
  try {
    final voices = [
      for (final v in (await tts.getVoices as List? ?? const []))
        if (v is Map) {'name': '${v['name'] ?? ''}', 'locale': '${v['locale'] ?? ''}'},
    ];
    int score(Map<String, String> v) {
      final name = v['name']!.toLowerCase();
      final locale = v['locale']!.toLowerCase().replaceAll('_', '-');
      var s = 0;
      if (chatStrings.isSomali && locale.startsWith('so')) s += 200;
      if (locale == 'en-us') s += 100; // American first
      if (locale.startsWith('en')) s += 10;
      if (RegExp(r'natural|neural|online|enhanced|premium|wavenet').hasMatch(name)) s += 30;
      if (name.contains('google')) s += 20;
      if (name.contains('samantha')) s += 15; // iPhone's natural US voice
      if (name.contains('network')) s += 10; // Android's online (more natural) voices
      if (RegExp(r'compact|local|espeak').hasMatch(name)) s -= 15;
      return s;
    }

    final best = voices.isEmpty ? null : (voices..sort((a, b) => score(b).compareTo(score(a)))).first;
    if (best != null && score(best) >= 100) {
      await tts.setVoice(best);
    } else {
      await tts.setLanguage('en-US'); // no list of voices: at least the American accent
    }
  } catch (_) {
    // Keep the device's default voice.
  }
}
