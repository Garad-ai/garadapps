import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'chat_strings.dart';

/// Makes [tts] speak like a native American man: the most natural US English male voice the phone
/// or browser has, instead of a female, British or robotic default. Somali users get a Somali voice
/// when the device has one. Used by Read aloud and calls.
Future<void> useAmericanVoice(FlutterTts tts) async {
  try {
    final voices = [
      for (final v in (await tts.getVoices as List? ?? const []))
        if (v is Map)
          {
            'name': '${v['name'] ?? ''}',
            'locale': '${v['locale'] ?? ''}',
            // iPhones say which voices are male and how good they are.
            'gender': '${v['gender'] ?? ''}',
            'quality': '${v['quality'] ?? ''}',
            'identifier': '${v['identifier'] ?? ''}',
          },
    ];
    final best = bestAmericanVoice(voices, somali: chatStrings.isSomali);
    if (best != null) {
      await tts.setVoice({
        'name': best['name']!,
        'locale': best['locale']!,
        if ((best['identifier'] ?? '').isNotEmpty) 'identifier': best['identifier']!,
      });
    } else {
      await tts.setLanguage('en-US'); // no American voice listed: at least the American accent
    }
  } catch (_) {
    // Keep the device's default voice.
  }
}

/// Google's on-device US voices on Android, by code: the male ones, best first ("Male voice 1, 2, 3
/// (US)"), and the female ones. Android does not say a voice's gender; these are its voice codes.
const _androidMaleUs = ['x-iom', 'x-iol', 'x-tpd'];
const _androidFemaleUs = ['x-tpc', 'x-iob', 'x-iog', 'x-tpf', 'x-sfg'];

/// Natural male voices in browsers and desktops (Edge, Windows, Chrome OS, Safari / iPhone).
final _maleNames = RegExp(
  r'\b(guy|andrew|brian|christopher|eric|roger|steffan|davis|tony|jason|david|mark|aaron|evan|nathan|tom|reed|alex)\b'
  r'|google us english [346]\b',
);
final _femaleNames = RegExp(
  r'\b(aria|jenny|michelle|ava|emma|ana|sara|nancy|jane|zira|samantha|allison|susan|victoria|karen|moira|tessa|nicky|joelle|zoe|libby|sonia|serena)\b'
  r'|google us english( [12578])?\s*(\(|$)',
);
// Apple's novelty and old robotic voices.
final _novelty = RegExp(
  r'\b(albert|bad news|bahh|bells|boing|bubbles|cellos|fred|good news|jester|junior|kathy|organ|ralph|superstar|trinoids|whisper|wobble|zarvox)\b',
);

/// The voice to use from [voices] (maps with name, locale and, on iPhones, gender and quality): a
/// natural-sounding American man when there is one; any American voice otherwise (the most natural);
/// for Somali users a Somali voice first. Null when none is American (or Somali).
@visibleForTesting
Map<String, String>? bestAmericanVoice(List<Map<String, String>> voices, {bool somali = false}) {
  int score(Map<String, String> v) {
    final name = (v['name'] ?? '').toLowerCase();
    final locale = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');
    final gender = (v['gender'] ?? '').toLowerCase();
    final quality = (v['quality'] ?? '').toLowerCase();
    var s = 0;
    if (somali && locale.startsWith('so')) s += 200;
    if (locale == 'en-us') s += 100; // American first
    if (locale.startsWith('en')) s += 10;
    // A man's voice.
    final androidMale = _androidMaleUs.indexWhere(name.contains);
    if (gender == 'male') {
      s += 60;
    } else if (androidMale >= 0) {
      s += 60 - androidMale; // "Male voice 1" first
    } else if (_maleNames.hasMatch(name)) {
      s += 55;
    } else if (gender == 'female' || _androidFemaleUs.any(name.contains) || _femaleNames.hasMatch(name)) {
      s -= 10;
    }
    // A natural one (neural / online / enhanced), not a robotic one.
    if (RegExp(r'natural|neural|online|wavenet').hasMatch(name)) s += 30;
    if (quality == 'premium') s += 30;
    if (quality == 'enhanced' || name.contains('enhanced')) s += 20;
    if (name.contains('google')) s += 20;
    if (name.contains('network')) s += 10; // Android's online (more natural) voices
    if (RegExp(r'compact|local|espeak').hasMatch(name)) s -= 15;
    if (_novelty.hasMatch(name)) s -= 100;
    return s;
  }

  if (voices.isEmpty) return null;
  final best = (List.of(voices)..sort((a, b) => score(b).compareTo(score(a)))).first;
  final locale = (best['locale'] ?? '').toLowerCase().replaceAll('_', '-');
  final usable = locale == 'en-us' || (somali && locale.startsWith('so'));
  return usable ? best : null;
}
