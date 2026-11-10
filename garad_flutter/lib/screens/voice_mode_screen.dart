import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../american_voice.dart';
import '../call_audio.dart';
import '../api/models.dart';
import '../chat_strings.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/answer_view.dart';
import '../widgets/model_picker.dart';

/// The answer to one spoken turn: the reply text, or a failure (with an optional message).
class VoiceReply {
  const VoiceReply(this.text) : error = null;
  const VoiceReply.failed(this.error) : text = null;

  final String? text;
  final String? error;
}

enum _Phase { starting, listening, thinking, speaking, paused, unavailable }

/// Words that are never a whole question on their own: fillers and joining words the microphone
/// catches from noise or a half-started sentence ("and", "um"…).
const _strayWords = {
  'and', 'um', 'umm', 'uh', 'uhm', 'er', 'erm', 'ah', 'eh', 'hmm', 'hm', 'mm', 'mhm', //
  'so', 'the', 'a', 'an', 'but', 'or', 'of', 'to', 'is', 'it', 'ee', 'oo', 'iyo',
};

/// True when [heard] is just one stray filler word (see [_strayWords]), not something to answer.
@visibleForTesting
bool isStrayWord(String heard) {
  final words = heard.toLowerCase().replaceAll(RegExp(r"[^\p{L}\s']", unicode: true), ' ').trim().split(RegExp(r'\s+'));
  return words.length == 1 && _strayWords.contains(words.single);
}

/// Live voice, Gemini-style: a light screen with a Garad-purple glow that moves with the voices,
/// captions, and the controls 📹 camera · ⬆ photo · ◉ (tap to interrupt) · 🎤 mute · ✕ end.
///
/// listen → (user stops talking) → ask Garad → speak the answer → listen again, until the user ends.
/// With the camera on it is a video call: each question goes with a picture of what the camera sees.
/// A shared photo goes with the next question.
class VoiceModeScreen extends StatefulWidget {
  const VoiceModeScreen({
    super.key,
    required this.ask,
    required this.cancel,
    this.upload,
    this.userName = '',
    this.models = const [],
    this.modelId,
    this.onModelChanged,
    this.onNewChat,
    this.voices = const [],
    this.voiceId,
    this.onVoiceChanged,
    this.synthesize,
  });

  /// AI voices to choose from (⋯ → Voice) and the one in use; null = the phone's own voice.
  final List<AiVoice> voices;
  final String? voiceId;
  final ValueChanged<String?>? onVoiceChanged;

  /// Speech for a sentence in an AI voice (MP3). Null: only the phone's voice.
  final Future<Uint8List> Function(String voiceId, String text)? synthesize;

  /// Sends what the user said (and any image references) through the chat — so it is saved —
  /// and returns Garad's answer.
  /// [onText] receives the answer so far while it streams, so speaking can start before it ends.
  final Future<VoiceReply> Function(String text, List<String> images, ValueChanged<String> onText) ask;

  /// Stores an image for a question; returns its reference. Null hides the camera and photo buttons.
  final Future<String> Function(Uint8List bytes)? upload;

  /// Stops waiting for an answer (when the user interrupts while Garad is thinking).
  final VoidCallback cancel;

  /// For "Let's talk, Amina".
  final String userName;

  /// The AI models to choose from (⋯ menu) and the one in use.
  final List<ChatModelInfo> models;
  final String? modelId;
  final ValueChanged<String>? onModelChanged;

  /// Start a new chat (voice continues in it).
  final VoidCallback? onNewChat;

  @override
  State<VoiceModeScreen> createState() => _VoiceModeScreenState();
}

class _VoiceModeScreenState extends State<VoiceModeScreen> with SingleTickerProviderStateMixin {
  final _stt = SpeechToText();
  final _tts = FlutterTts();

  /// Plays the AI voices' audio.
  final _player = AudioPlayer();
  late final StreamSubscription<void> _playerDone;

  /// The AI voice in use (see [VoiceModeScreen.voices]); null = the phone's own voice.
  String? _voiceId;

  /// AI-voice audio already requested for queued sentences, so the next one is ready when the
  /// current one ends.
  final Map<String, Future<Uint8List>> _audio = {};

  /// What the user asked last (shown above Garad's answer in the captions).
  String _question = '';

  /// The sentence Garad is saying right now (the caption shows it, not the whole answer).
  String _saying = '';
  final _random = math.Random();

  late final AnimationController _clock;

  _Phase _phase = _Phase.starting;
  String _heard = '';
  String _reply = '';
  String? _error;
  bool _gotFinal = false;
  int _turn = 0;

  /// Sends the sentence when the words stop changing (see [_listen]).
  Timer? _silence;

  /// Captions on screen (the CC button).
  bool _captions = true;

  /// 🔊 off: answers are shown, not spoken.
  bool _speaker = true;

  /// Speaking speed: 0.8 slow, 1 normal, 1.25 fast.
  double _speed = 1;
  String? _modelId;

  /// The last answer, kept on screen while listening again.
  String _lastReply = '';

  /// Voice energy 0..1: follows the microphone while listening, each spoken word while speaking.
  double _level = 0;
  double _target = 0;
  DateTime _lastBump = DateTime.fromMillisecondsSinceEpoch(0);

  // ---- Camera (video call) and shared photo ----

  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool get _cameraOn => _camera?.value.isInitialized ?? false;

  /// A photo shared with ⬆, sent with the next question (uploading in the background).
  Uint8List? _photo;
  Future<String>? _photoRef;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..addListener(_tick)
      ..repeat();
    // iPhone: speak through the loudspeaker while the microphone is open, with the phone's echo
    // cancellation (voice-chat mode), so Garad stays audible and does not hear itself as the user.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) _setUpIosAudio();
    // An AI voice whenever there are any (an American one unless another was picked) — the phone's
    // own voice only when the server has none.
    _voiceId =
        widget.voiceId ??
        (widget.voices.where((v) => v.description.contains('American')).firstOrNull ?? widget.voices.firstOrNull)?.id;
    _playerDone = _player.onPlayerComplete.listen((_) => _onSpokenDone());
    _tts.setCompletionHandler(_onSpokenDone);
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((_) => _onSpokenDone());
    // Each word Garad speaks gives the glow a pulse.
    _tts.setProgressHandler((text, start, end, word) => _bump(0.55 + _random.nextDouble() * 0.45));
    _modelId = widget.modelId;
    _applySpeed();
    useAmericanVoice(_tts);
    _start();
  }

  @override
  void dispose() {
    _clock.dispose();
    _silence?.cancel();
    _stt.cancel();
    _tts.stop();
    _playerDone.cancel();
    _player.dispose();
    _camera?.dispose();
    _focusRing?.cancel();
    CallAudio.restore();
    super.dispose();
  }

  /// Both audio plugins set the iPhone's one audio session, and the last one wins: the AI voices'
  /// player first, then the phone voice's voice-chat mode (its echo cancellation is what makes
  /// cutting in by talking safe — see [_canBargeIn]).
  Future<void> _setUpIosAudio() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.allowBluetooth,
              AVAudioSessionOptions.allowBluetoothA2DP,
            },
          ),
        ),
      );
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playAndRecord, [
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
      ], IosTextToSpeechAudioMode.voiceChat);
    } catch (_) {
      // Keep the phone's default audio setup.
    }
  }

  /// Stops Garad's voice — the phone's and the AI voice — and forgets audio fetched for this answer.
  Future<void> _stopVoice() async {
    _audio.clear();
    // Never let stopping hold up listening (some engines answer slowly, or not at all, when idle).
    const limit = Duration(milliseconds: 400);
    await Future.wait([
      _tts.stop().timeout(limit, onTimeout: () => null),
      if (_player.state == PlayerState.playing || _player.state == PlayerState.paused)
        _player.stop().timeout(limit, onTimeout: () {}),
    ]);
  }

  // ---- Animation ----

  void _tick() {
    final now = DateTime.now();
    var target = _target;
    switch (_phase) {
      case _Phase.speaking:
        // No word events for a moment (some voices send none): keep a natural talking motion.
        if (now.difference(_lastBump) > const Duration(milliseconds: 450)) {
          final t = now.millisecondsSinceEpoch / 1000;
          target = 0.35 + 0.22 * math.sin(t * 7.3) * math.sin(t * 2.1) + _random.nextDouble() * 0.12;
        }
      case _Phase.thinking:
        target = 0.18 + 0.1 * math.sin(now.millisecondsSinceEpoch / 260);
      case _Phase.paused || _Phase.unavailable || _Phase.starting:
        target = 0.03;
      case _Phase.listening:
        break;
    }
    _level += (target - _level) * 0.12;
    _target *= 0.94; // word and mic pulses fade
  }

  void _bump(double value) {
    _lastBump = DateTime.now();
    if (value > _target) _target = value;
  }

  // ---- Conversation loop ----

  Future<void> _start() async {
    void onStatus(String status) {
      // While Garad talks, keep the ears open so the user can cut in.
      if ((status == 'done' || status == 'notListening') && _phase == _Phase.speaking) {
        final turn = _turn;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _phase == _Phase.speaking && turn == _turn && !_stt.isListening) _startBargeIn();
        });
        return;
      }
      if ((status == 'done' || status == 'notListening') && _phase == _Phase.listening && !_gotFinal) {
        // Stopped after hearing words but without a "final" result (common in Chrome): send them.
        if (_heard.trim().isNotEmpty) {
          _finish();
          return;
        }
        // Stopped without hearing anything: listen again.
        final turn = _turn;
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted && _phase == _Phase.listening && turn == _turn && !_stt.isListening) _listen();
        });
      }
    }

    void onError(SpeechRecognitionError e) {
      if (!mounted) return;
      final code = e.errorMsg.toLowerCase();
      // Permanent: the microphone is blocked or missing — say so instead of "Listening…" forever.
      if (code.contains('not-allowed') ||
          code.contains('permission') ||
          code.contains('service-not-allowed') ||
          code.contains('audio-capture') ||
          code.contains('error_audio')) {
        _turn++;
        setState(() {
          _phase = _Phase.unavailable;
          _error = _t(
            'Makarafoonka waa la xiray. U oggolow (calaamadda 🔒 ee ciwaanka, ama dejinta taleefanka), kadib taabo 🎤.',
            'The microphone is blocked. Allow it (the 🔒 icon by the address, or the phone settings), then tap 🎤.',
          );
        });
        return;
      }
      // No connection to the speech service: show it, and keep trying.
      if (code.contains('network')) {
        _flash(
          _t('Adeegga codka lama gaari karo. Hubi internetka.', "Can't reach the speech service. Check the internet."),
        );
      }
      if (_phase == _Phase.listening) {
        // Words already heard are not thrown away.
        if (_heard.trim().isNotEmpty && !_gotFinal) {
          _finish();
          return;
        }
        final turn = _turn;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && _phase == _Phase.listening && turn == _turn && !_stt.isListening) _listen();
        });
      }
    }

    final ok = await _stt.initialize(onStatus: onStatus, onError: onError);
    // SpeechToText is one shared object and initialize() only sets these the first time (a second call,
    // or after dictating in the chat, would keep the old ones and never hear "done" or errors here).
    _stt
      ..statusListener = onStatus
      ..errorListener = onError;
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _phase = _Phase.unavailable;
        _error = chatStrings.micUnavailable;
      });
      return;
    }
    await _listen();
  }

  Future<void> _listen() async {
    if (!mounted) return;
    // Don't wait long for the voice to stop: in browsers this can hang when nothing is speaking.
    _speechQueue.clear();
    _speakingChunk = false;
    await _stopVoice();
    _silence?.cancel();
    _turn++;
    setState(() {
      _phase = _Phase.listening;
      _heard = '';
      _error = null;
      _gotFinal = false;
    });

    // The ears are still open from while Garad was talking: keep that session for this turn
    // (everything it heard so far was Garad's own voice or noise).
    if (_stt.isListening) {
      if (_canBargeIn) {
        _dropWords = _words(_transcript).length;
        return;
      }
      // Without echo cancellation that session may have heard Garad: start a clean one.
      await _stt.cancel();
      if (!mounted || _phase != _Phase.listening) return;
    }

    // Somali recognition for Somali users when the phone has it; otherwise the phone's default.
    if (chatStrings.isSomali && _localeId == null) {
      final locales = await _stt.locales();
      _localeId = locales.where((l) => l.localeId.toLowerCase().startsWith('so')).firstOrNull?.localeId;
    }
    if (!mounted || _phase != _Phase.listening) return;

    final turn = _turn;
    try {
      await _listenNow(_localeId);
    } catch (e) {
      // The engine refused to start (e.g. still busy in a browser): reset it and try again shortly.
      await _stt.cancel();
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && _phase == _Phase.listening && turn == _turn) _listen();
      });
    }
  }

  Future<void> _listenNow(String? localeId) async {
    _transcript = '';
    _dropWords = 0;
    // Android: no start/stop beep each time the recognizer opens (sent first, so it lands first).
    CallAudio.quiet();
    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        _transcript = result.recognizedWords;
        if (_phase == _Phase.speaking) {
          if (_canBargeIn) _maybeBargeIn();
          return;
        }
        if (_phase != _Phase.listening) return;
        // The recogniser itself is very unsure of this sentence: typically an echo of Garad or
        // background noise, not the user. Drop it and keep listening.
        if (result.finalResult && result.hasConfidenceRating && result.confidence > 0 && result.confidence < 0.4) {
          _silence?.cancel();
          setState(() => _heard = '');
          return;
        }
        // Leave out what was heard before this turn (Garad's own voice while it was talking).
        final words = _words(result.recognizedWords).skip(_dropWords).join(' ');
        // Browsers give no sound level: let new words move the glow instead.
        if (words.length > _heard.length) _bump(0.4 + _random.nextDouble() * 0.3);
        setState(() => _heard = words);
        if (result.finalResult && words.trim().isNotEmpty) {
          _finish();
          return;
        }
        // The words stopped changing for a moment: the user has finished (even if the browser
        // never sends a "final" result).
        _silence?.cancel();
        if (words.trim().isNotEmpty) {
          _silence = Timer(const Duration(milliseconds: 1100), () {
            if (mounted && _phase == _Phase.listening && !_gotFinal && _heard == words) _finish();
          });
        }
      },
      // Android reports about -2..10 dB; iOS a similar range. Map it to 0..1.
      onSoundLevelChange: (level) => _bump(((level + 2) / 12).clamp(0.0, 1.0)),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
        // Phones end the sentence after a 2 s pause. Browsers would stop and restart every 2 s
        // before the user even speaks, so there the silence timer above ends the sentence instead.
        pauseFor: kIsWeb ? null : const Duration(milliseconds: 1500),
        listenFor: const Duration(seconds: 60),
      ),
    );
  }

  // ---- Cutting in while Garad talks (no need to tap) ----

  /// Everything the current listening session has heard, and how many of its first words are not
  /// part of the user's turn (Garad's own voice picked up by the microphone).
  String _transcript = '';
  int _dropWords = 0;
  String? _localeId;

  static List<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[^\p{L}\p{N}\s']", unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// Cutting in by talking needs the phone to cancel Garad's own voice from the microphone (echo
  /// cancellation). Only an iPhone speaking with its own voice in voice-chat mode does that reliably;
  /// browsers, most Android phones and the AI voices' player do not, and then the microphone "hears"
  /// Garad and sends made-up words as the user's question. There, tap the pill to interrupt instead.
  bool get _canBargeIn => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && _voiceId == null;

  /// Starts listening while Garad talks.
  Future<void> _startBargeIn() async {
    if (!mounted || !_canBargeIn || _phase != _Phase.speaking || _stt.isListening) return;
    try {
      await _listenNow(_localeId);
    } catch (_) {
      // Not this time: the next sentence tries again.
    }
  }

  /// While Garad talks: if the microphone hears the user (at least 2 words that are not
  /// Garad's own), Garad stops and the user's words become the next question.
  void _maybeBargeIn() {
    final said = _words(_reply).toSet();
    final heard = _words(_transcript).skip(_dropWords).toList();
    final firstOwn = heard.indexWhere((w) => !said.contains(w));
    if (firstOwn < 0 || heard.where((w) => !said.contains(w)).length < 2) return;

    _turn++; // the rest of the answer is not spoken
    if (!_replyDone) widget.cancel();
    _speechQueue.clear();
    _speakingChunk = false;
    _stopVoice();
    _dropWords += firstOwn;
    final words = heard.skip(firstOwn).join(' ');
    setState(() {
      _phase = _Phase.listening;
      _heard = words;
      _gotFinal = false;
      _error = null;
    });
    _silence?.cancel();
    _silence = Timer(const Duration(milliseconds: 1100), () {
      if (mounted && _phase == _Phase.listening && !_gotFinal && _heard == words) _finish();
    });
  }

  /// The user finished a sentence: send what was heard (once per turn).
  void _finish() {
    if (_gotFinal || _heard.trim().isEmpty) return;
    // Only a stray filler word ("and", "um"…): background noise or a half-start, not a question.
    // Keep listening instead of sending it. (Real one-word replies — yes, no, hi, haa — still go.)
    if (isStrayWord(_heard)) {
      _silence?.cancel();
      _dropWords = _words(_transcript).length; // a restarted sentence does not start with it
      setState(() => _heard = '');
      if (!_stt.isListening) _listen();
      return;
    }
    _gotFinal = true;
    _silence?.cancel();
    _ask(_heard.trim());
  }

  Future<void> _ask(String text) async {
    await _stt.stop();
    if (!mounted) return;
    final turn = ++_turn;
    setState(() {
      _phase = _Phase.thinking;
      _question = text;
      _saying = '';
      _reply = '';
    });

    // What Garad should see with this question: the shared photo, and the camera's view right now.
    final images = <String>[];
    final photo = _photoRef;
    if (photo != null) {
      try {
        images.add(await photo);
      } catch (_) {
        // Upload failed: ask without it.
      }
      if (mounted) {
        setState(() {
          _photo = null;
          _photoRef = null;
        });
      }
    }
    if (_cameraOn) {
      // Taken now that the user has finished asking: by then they are holding up what they mean
      // ("calculate this"), steady — not while they were still moving it into view.
      final frame = await _captureFrame();
      if (frame != null) images.add(frame);
    }
    if (!mounted || turn != _turn) return; // interrupted meanwhile

    // Speak the answer sentence by sentence while it is still arriving (no waiting for the end).
    _speechQueue.clear();
    _spokenUpTo = 0;
    _queuedText = '';
    _replyDone = false;
    final reply = await widget.ask(text, images, (soFar) {
      if (!mounted || turn != _turn) return;
      setState(() => _reply = soFar);
      _queueSentences(soFar, finished: false);
    });
    if (!mounted || turn != _turn) return;

    final answer = reply.text;
    if (answer == null || answer.trim().isEmpty) {
      _speechQueue.clear();
      await _stopVoice();
      setState(() => _error = reply.error ?? chatStrings.somethingWrong);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (mounted && turn == _turn) _listen();
      return;
    }

    _lastReply = answer;
    setState(() => _reply = answer);
    if (!_speaker) {
      // Speaker off: show the answer and keep listening.
      await _listen();
      return;
    }
    _replyDone = true;
    _queueSentences(answer, finished: true);
    // Everything was already spoken while streaming: listen again.
    if (!_speakingChunk && _speechQueue.isEmpty) _listen();
  }

  // ---- Speaking while the answer streams ----

  final List<String> _speechQueue = [];
  int _spokenUpTo = 0;

  /// The answer text up to [_spokenUpTo], as it was when queued (to notice a restarted answer).
  String _queuedText = '';
  bool _speakingChunk = false;
  bool _replyDone = false;

  /// Queues the finished sentences of [text] not queued yet (all of it when [finished]).
  void _queueSentences(String text, {required bool finished}) {
    if (!_speaker) return;
    // The text no longer starts with what was already queued: the server restarted the answer (after
    // a tool such as creating an image). Speak the new answer from its start — not from the middle of
    // a word, and not nothing at all.
    if (!text.startsWith(_queuedText)) _spokenUpTo = 0;
    final pending = text.substring(_spokenUpTo);
    var end = pending.length;
    if (!finished) {
      // Up to the last sentence end (. ! ? … or a new line) followed by a space or line break.
      final ends = RegExp(r'[.!?…\n](?=\s)').allMatches(pending);
      if (ends.isEmpty) return;
      end = ends.last.end;
    }
    final chunk = _speakable(pending.substring(0, end));
    _spokenUpTo += end;
    _queuedText = text.substring(0, _spokenUpTo);
    if (chunk.isEmpty) return;
    // One sentence at a time, so the caption shows exactly what is being said.
    final voice = _voiceId;
    final synthesize = widget.synthesize;
    for (final sentence in chunk.split(RegExp(r'(?<=[.!?…])\s+'))) {
      if (sentence.trim().isEmpty) continue;
      _speechQueue.add(sentence);
      // AI voice: ask for this sentence's audio now, so it is ready when its turn comes.
      if (voice != null && synthesize != null) {
        final audio = synthesize(voice, sentence);
        audio.ignore(); // a failure is handled when the sentence is spoken
        _audio[sentence] = audio;
      }
    }
    if (_phase != _Phase.speaking) {
      setState(() => _phase = _Phase.speaking);
      _lastBump = DateTime.now();
      if (_canBargeIn) {
        _startBargeIn(); // the user can cut in by just talking
      } else if (_stt.isListening) {
        _stt.cancel(); // the microphone would hear Garad as the user
      }
    }
    _speakNext();
  }

  void _speakNext() {
    if (_speakingChunk || _speechQueue.isEmpty) return;
    _speakingChunk = true;
    final text = _speechQueue.removeAt(0);
    final audio = _audio.remove(text);
    // The sound quieted while listening is back before Garad's voice plays.
    CallAudio.restore();
    if (audio == null) {
      setState(() => _saying = text); // the caption appears with the voice
      _tts.speak(text); // the phone's voice
    } else {
      // The AI voice's audio may still be on its way: the caption waits for it (see _playAudio), so
      // text and voice start together instead of the words showing a second early.
      _playAudio(audio, text);
    }
  }

  /// Plays a sentence in the AI voice. If its audio does not come, it is asked for again (twice) in
  /// the same voice — never switching to the phone's robotic voice mid-call. If it still fails, the
  /// sentence stays on screen as a caption and the call goes on.
  Future<void> _playAudio(Future<Uint8List> audio, String text) async {
    final turn = _turn;
    final voice = _voiceId;
    final synthesize = widget.synthesize;
    for (var attempt = 0; ; attempt++) {
      try {
        final bytes = await audio;
        if (!mounted || turn != _turn || !_speakingChunk) return; // interrupted meanwhile
        setState(() => _saying = text); // the caption appears as the voice starts
        await _player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
        // ⋯ Slow / Normal / Fast for the AI voices too (players keep the pitch, only the pace changes).
        if (_speed != 1) await _player.setPlaybackRate(_speed);
        return;
      } catch (_) {
        if (!mounted || turn != _turn || !_speakingChunk) return;
        if (attempt < 2 && voice != null && synthesize != null) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          audio = synthesize(voice, text);
          continue;
        }
        // No voice for this sentence: show it as a caption, give the reader time, then carry on.
        setState(() => _saying = text);
        await Future<void>.delayed(Duration(milliseconds: 600 + 50 * text.length));
        if (mounted && turn == _turn && _speakingChunk) _onSpokenDone();
        return;
      }
    }
  }

  void _onSpokenDone() {
    _speakingChunk = false;
    if (!mounted || _phase != _Phase.speaking) return;
    if (_speechQueue.isNotEmpty) {
      _speakNext();
    } else if (_replyDone) {
      if (_canBargeIn) {
        _listen();
      } else {
        // A short pause first, so the end of Garad's voice (still in the room) is not heard as the user.
        final turn = _turn;
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && turn == _turn && _phase == _Phase.speaking) _listen();
        });
      }
    }
    // Otherwise more of the answer is still arriving: the next sentence starts it again.
  }

  /// Tap on the glowing pill: stop Garad (speaking or thinking) and listen; or resume when muted.
  Future<void> _interrupt() async {
    switch (_phase) {
      case _Phase.speaking:
        _turn++; // the rest of a still-streaming answer is not spoken
        _speechQueue.clear();
        if (!_replyDone) widget.cancel();
        await _stopVoice();
        await _listen();
      case _Phase.thinking:
        _turn++;
        widget.cancel();
        await _listen();
      case _Phase.paused:
        await _listen();
      case _Phase.unavailable:
        await _start();
      case _Phase.listening || _Phase.starting:
        break;
    }
  }

  /// 🎤: mute (Garad stops listening) / unmute.
  Future<void> _toggleMute() async {
    if (_phase == _Phase.unavailable) return _start();
    if (_phase == _Phase.paused) return _listen();
    _turn++;
    await _stt.stop();
    await _stopVoice();
    CallAudio.restore();
    if (_phase == _Phase.thinking) widget.cancel();
    if (mounted) setState(() => _phase = _Phase.paused);
  }

  // ---- Camera and photo ----

  Future<void> _toggleCamera() async {
    final current = _camera;
    if (current != null) {
      setState(() => _camera = null);
      await current.dispose();
      return;
    }
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('none', 'No camera');
      // The back camera first (show Garad the world); the flip button switches to the front.
      final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _cameraIndex = back < 0 ? 0 : back;
      await _openCamera();
    } catch (_) {
      _flash(_t('Kamaradda lama heli karo. Hubi oggolaanshaha.', 'The camera is not available. Check the permission.'));
    }
  }

  Future<void> _openCamera() async {
    final controller = CameraController(
      _cameras[_cameraIndex],
      // Full HD: sharp enough for Garad to read handwriting, numbers and small print on paper or a
      // screen (medium, 480p, turned a written sum into blur). Still well under 1 MB per picture.
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    final old = _camera;
    setState(() => _camera = controller);
    await old?.dispose();
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _focusPoint = null; // the other camera starts focused on the middle
    try {
      await _openCamera();
    } catch (_) {
      _flash(_t('Kamaradda lama beddeli karo.', 'Could not switch the camera.'));
    }
  }

  /// Where the user last tapped the camera picture (0..1 of the screen), shown as a ring for a moment.
  Offset? _focusPoint;
  Timer? _focusRing;

  Future<void> _focusAt(Offset point) async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    final p = Offset(point.dx.clamp(0.0, 1.0), point.dy.clamp(0.0, 1.0));
    setState(() => _focusPoint = p);
    _focusRing?.cancel();
    _focusRing = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() {}); // the ring fades; the point is kept for the next picture
    });
    try {
      await Future.wait([camera.setFocusPoint(p), camera.setExposurePoint(p)]);
    } catch (_) {
      // Not supported on this camera.
    }
  }

  /// A picture of what the camera sees now, uploaded; null if that fails.
  Future<String?> _captureFrame() async {
    final camera = _camera;
    final upload = widget.upload;
    if (camera == null || upload == null || !camera.value.isInitialized || camera.value.isTakingPicture) return null;
    try {
      // Sharp, not "good enough": focus and expose on what the user tapped (or the middle, where
      // people hold a page) and give the lens a moment to settle before the picture.
      final point = _focusPoint ?? const Offset(0.5, 0.5);
      try {
        await Future.wait([camera.setFocusPoint(point), camera.setExposurePoint(point)]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } catch (_) {
        // This camera can't focus on a point: take it as it is.
      }
      final bytes = await (await camera.takePicture()).readAsBytes();
      return await upload(bytes);
    } catch (_) {
      return null;
    }
  }

  /// ⬆: share a photo; it goes with the next thing the user says.
  Future<void> _pickPhoto() async {
    final upload = widget.upload;
    if (upload == null) return;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final ref = upload(bytes);
      ref.ignore(); // awaited with the next question; an error there is handled then
      setState(() {
        _photo = bytes;
        _photoRef = ref;
      });
    } catch (_) {
      _flash(_t('Sawirka lama furi karo.', 'Could not open the photo.'));
    }
  }

  // ---- Settings (⋯) ----

  Future<void> _applySpeed() async {
    // Normal speed is 0.5 for the phone voices and 1.0 for the browser's.
    final normal = kIsWeb ? 1.0 : 0.5;
    await _tts.setSpeechRate((normal * _speed).clamp(0.1, kIsWeb ? 2.0 : 1.0));
    // An AI-voice sentence playing now changes pace straight away; the next ones follow in _playAudio.
    if (_player.state == PlayerState.playing) await _player.setPlaybackRate(_speed);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speaker = !_speaker);
    if (!_speaker && _phase == _Phase.speaking) {
      await _stopVoice();
      await _listen();
    }
  }

  Future<void> _pickModel() async {
    final picked = await showModelPicker(context, models: widget.models, selectedId: _modelId);
    if (picked == null || !mounted) return;
    setState(() => _modelId = picked);
    widget.onModelChanged?.call(picked);
  }

  /// ⋯ → Voice: the phone's own voice, or one of the AI people. Picking one says hello in it.
  Future<void> _pickVoice() async {
    final c = Palette.of(context);
    // '' = the phone's voice (null would mean "closed without choosing").
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        Widget option(String id, String name, String description, IconData icon) => ListTile(
          leading: CircleAvatar(
            backgroundColor: c.brandSoft,
            child: Icon(icon, color: c.brand, size: 20),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(description),
          trailing: (_voiceId ?? '') == id ? Icon(Icons.check_circle, color: c.brand) : null,
          onTap: () => Navigator.pop(sheet, id),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    _t('Dooro codka Garad', "Choose Garad's voice"),
                    style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                // OpenAI's usage policy: tell people the voice they hear is AI-generated.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _t(
                      'Codadka AI-ga waxaa sameeyay AI — ma aha dad dhab ah.',
                      'AI voices are AI-generated — not real people.',
                    ),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ),
                // The phone's robotic voice is offered only when the server has no AI voices.
                if (widget.voices.isEmpty)
                  option(
                    '',
                    _t('Codka taleefanka', 'Phone voice'),
                    _t('Bilaash · wuxuu shaqeeyaa internet la’aan', 'Free · works offline'),
                    Icons.smartphone,
                  ),
                for (final v in widget.voices) option(v.id, v.name, v.description, Icons.graphic_eq),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    final id = picked.isEmpty ? null : picked;
    setState(() => _voiceId = id);
    widget.onVoiceChanged?.call(id);
    final name = widget.voices.where((v) => v.id == id).firstOrNull?.name;
    if (_speaker && name != null) _sayHello(name);
  }

  /// "Hi, I'm Amina." in the voice just picked — spoken like an answer, so the microphone ignores it
  /// and listening resumes after.
  Future<void> _sayHello(String name) async {
    _turn++;
    _speechQueue.clear();
    _speakingChunk = false;
    await _stopVoice();
    if (!mounted) return;
    final hello = _t('Salaan, waxaan ahay $name. Aan wada hadalno.', "Hi, I'm $name. Let's talk.");
    setState(() {
      _reply = hello;
      _lastReply = hello;
    });
    _spokenUpTo = 0;
    _queuedText = '';
    _replyDone = true;
    _queueSentences(hello, finished: true);
  }

  Future<void> _menu() async {
    final model = widget.models.where((m) => m.id == _modelId).firstOrNull;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.models.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: Text(chatStrings.model),
                    trailing: Text(model?.shortName ?? '', style: TextStyle(color: Palette.of(context).muted)),
                    onTap: () {
                      Navigator.pop(sheet);
                      _pickModel();
                    },
                  ),
                if (widget.voices.isNotEmpty && widget.synthesize != null)
                  ListTile(
                    leading: const Icon(Icons.record_voice_over_outlined),
                    title: Text(_t('Codka', 'Voice')),
                    trailing: Text(
                      widget.voices.where((v) => v.id == _voiceId).firstOrNull?.name ?? _t('Taleefanka', 'Phone'),
                      style: TextStyle(color: Palette.of(context).muted),
                    ),
                    onTap: () {
                      Navigator.pop(sheet);
                      _pickVoice();
                    },
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: Text(chatStrings.readAloud),
                  value: _speaker,
                  onChanged: (_) {
                    _toggleSpeaker();
                    setSheet(() {});
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SegmentedButton<double>(
                    segments: [
                      ButtonSegment(value: 0.8, label: Text(_t('Tartiib', 'Slow'))),
                      ButtonSegment(value: 1.0, label: Text(_t('Caadi', 'Normal'))),
                      ButtonSegment(value: 1.25, label: Text(_t('Degdeg', 'Fast'))),
                    ],
                    selected: {_speed},
                    style: SegmentedButton.styleFrom(
                      selectedForegroundColor: Colors.white,
                      selectedBackgroundColor: Palette.of(context).brand,
                    ),
                    onSelectionChanged: (value) {
                      setState(() => _speed = value.first);
                      setSheet(() {});
                      _applySpeed();
                    },
                  ),
                ),
                if (widget.onNewChat != null)
                  ListTile(
                    leading: const Icon(Icons.add_comment_outlined),
                    title: Text(chatStrings.newChat),
                    onTap: () {
                      Navigator.pop(sheet);
                      widget.onNewChat!();
                      setState(() {
                        _lastReply = '';
                        _heard = '';
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _flash(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _error == message) setState(() => _error = null);
    });
  }

  static String _t(String so, String en) => chatStrings.isSomali ? so : en;

  /// Words to say (and show as captions): no Markdown symbols, list bullets, emojis, code, file
  /// cards, image codes or web addresses. List lines become sentences instead of "- item - item".
  static String _speakable(String markdown) => markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'\[\[GARAD_[A-Z_]+:[^\]]*\]\]'), '')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
      .replaceAll(RegExp(r'https?://\S+'), '')
      // "- item", "* item", "• item", "1. item" at the start of a line: just the item.
      .replaceAll(RegExp(r'^[ \t]*(?:[-*•–]|\d+[.)])[ \t]+', multiLine: true), '')
      .replaceAll(RegExp(r'[*_`#>|~]'), '')
      // Emojis (voices read them out as words).
      .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]', unicode: true), '')
      // A line that ends without punctuation (a list item) ends as a sentence; other breaks: a space.
      .replaceAll(RegExp(r'(?<=[\p{L}\p{N})])[ \t]*\n+[ \t]*', unicode: true), '. ')
      .replaceAll(RegExp(r'[ \t]*\n+[ \t]*'), ' ')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();

  // ---- UI ----

  String get _status => switch (_phase) {
    _Phase.starting => '',
    _Phase.listening => chatStrings.listening,
    _Phase.thinking => _t('Waan ka fekerayaa…', 'Thinking…'),
    _Phase.speaking => _t('Taabo si aad u joojiso', 'Tap to interrupt'),
    _Phase.paused => _t('Makarafoonka waa xiran yahay', 'Microphone off'),
    _Phase.unavailable => _error ?? chatStrings.micUnavailable,
  };

  /// The newest words of [s] (about [length] letters), cut at a word, like live captions.
  static String _tail(String s, [int length = 220]) {
    final text = _speakable(s).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= length) return text;
    final cut = text.indexOf(' ', text.length - length);
    return '…${text.substring(cut < 0 ? text.length - length : cut + 1)}';
  }

  /// Live transcript, like a call app's captions: who is talking (YOU / GARAD) over what they say.
  /// While Garad answers, your question stays above it, smaller, and Garad's line is the sentence
  /// being spoken right now — it changes with the voice, sentence by sentence.
  Widget _captionsView({required Color textColor, required Color mutedColor, required bool onVideo}) {
    final you = _t('ADIGA', 'YOU');
    const garad = 'GARAD';
    // After the answer: the last sentence said (or, with the speaker off, the end of the answer).
    final lastSaid = _saying.isNotEmpty ? _saying : _tail(_lastReply, 140);
    final lines = <({String who, String text, bool main})>[
      if (_phase == _Phase.listening && _heard.isNotEmpty)
        (who: you, text: _heard, main: true)
      else if (_phase == _Phase.listening && lastSaid.isNotEmpty)
        (who: garad, text: lastSaid, main: false)
      else if (_phase == _Phase.thinking)
        (who: you, text: _question, main: true)
      else if (_phase == _Phase.speaking) ...[
        if (_question.isNotEmpty) (who: you, text: _question, main: false),
        if (_saying.isNotEmpty) (who: garad, text: _saying, main: true),
      ] else if (_phase == _Phase.paused && lastSaid.isNotEmpty)
        (who: garad, text: lastSaid, main: false),
    ];

    if (lines.isEmpty) {
      // Nothing said yet: a big, calm greeting.
      final first = widget.userName.trim().split(RegExp(r'\s+')).first;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _t(
              first.isEmpty ? 'Aan wada hadalno' : 'Aan wada hadalno, $first',
              first.isEmpty ? "Let's talk" : "Let's talk, $first",
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: serifFont, color: textColor, fontSize: 30, height: 1.25),
          ),
        ),
      );
    }

    final shadows = onVideo ? const [Shadow(color: Colors.black54, blurRadius: 8)] : null;
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines) ...[
              Text(
                line.who,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  shadows: shadows,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                line.text,
                maxLines: line.main ? 7 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: serifFont,
                  color: line.main ? textColor : mutedColor,
                  fontSize: line.main ? 23 : 16.5,
                  height: 1.35,
                  shadows: shadows,
                ),
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final muted = _phase == _Phase.paused || _phase == _Phase.unavailable;
    final canAttach = widget.upload != null;
    final c = Palette.of(context);
    // Over the camera picture: white text and glass buttons; otherwise the app's light page.
    final onVideo = _cameraOn;
    final textColor = onVideo ? Colors.white : c.text;
    final mutedColor = onVideo ? Colors.white70 : c.muted;
    final videoShadow = onVideo ? const [Shadow(color: Colors.black54, blurRadius: 6)] : null;

    return Scaffold(
      backgroundColor: onVideo ? Colors.black : c.background,
      body: Stack(
        children: [
          // Video call: what the camera sees fills the screen.
          if (camera != null && camera.value.isInitialized)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  // Tap the paper (or anything) to focus there.
                  onTapUp: (d) => _focusAt(Offset(d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: camera.value.previewSize?.height ?? 1080,
                          height: camera.value.previewSize?.width ?? 1920,
                          // The camera plugin shows the front camera like a mirror, which turns writing
                          // held up to it backwards. Show it the right way round — as Garad sees it.
                          child: camera.description.lensDirection == CameraLensDirection.front
                              ? Transform.flip(flipX: true, child: CameraPreview(camera))
                              : CameraPreview(camera),
                        ),
                      ),
                      if (_focusPoint case final p? when _focusRing?.isActive ?? false)
                        Positioned(
                          left: p.dx * box.maxWidth - 32,
                          top: p.dy * box.maxHeight - 32,
                          child: IgnorePointer(
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          // A soft Garad-purple glow from the bottom; it rises with your voice and Garad's.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _clock,
                builder: (_, _) => CustomPaint(
                  painter: _GlowPainter(level: muted ? 0 : _level, color: c.brand, onVideo: onVideo),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ☰ back to the chat · (flip camera) · [CC | ⋯]
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _RoundButton(
                        icon: Icons.notes_rounded,
                        tooltip: strings.close,
                        onVideo: onVideo,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      if (_cameraOn && _cameras.length > 1) ...[
                        _RoundButton(
                          icon: Icons.flip_camera_ios_outlined,
                          tooltip: _t('Beddel kamaradda', 'Flip camera'),
                          onVideo: onVideo,
                          onTap: _flipCamera,
                        ),
                        const SizedBox(width: 8),
                      ],
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: onVideo ? const Color(0x33FFFFFF) : c.surfaceStrong,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: onVideo ? const Color(0x22FFFFFF) : c.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _t('Qoraalka hadalka', 'Captions'),
                              onPressed: () => setState(() => _captions = !_captions),
                              icon: Icon(
                                _captions ? Icons.closed_caption : Icons.closed_caption_disabled_outlined,
                                color: textColor,
                                size: 21,
                              ),
                            ),
                            IconButton(
                              tooltip: chatStrings.more,
                              onPressed: _menu,
                              icon: Icon(Icons.more_horiz, color: textColor, size: 21),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // The middle: the live transcript (CC on), or Garad's orb (CC off).
                Expanded(
                  child: _captions
                      ? _captionsView(textColor: textColor, mutedColor: mutedColor, onVideo: onVideo)
                      : Center(
                          child: AnimatedBuilder(
                            animation: _clock,
                            builder: (_, _) => _Orb(level: muted ? 0 : _level),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _error ?? _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _error != null ? c.danger : mutedColor, fontSize: 13, shadows: videoShadow),
                  ),
                ),
                const SizedBox(height: 14),
                // A shared photo waiting for the next question.
                if (_photo case final photo?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(photo, width: 72, height: 72, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: -8,
                          top: -8,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _photo = null;
                              _photoRef = null;
                            }),
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: c.text,
                              child: Icon(Icons.close, size: 14, color: c.background),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // 📹 · ⬆ · ◉ · 🎤 · ✕
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _RoundButton(
                        icon: _cameraOn ? Icons.videocam : Icons.videocam_outlined,
                        tooltip: _t('Wicitaan muuqaal', 'Video'),
                        active: _cameraOn,
                        onVideo: onVideo,
                        onTap: canAttach ? _toggleCamera : null,
                      ),
                      _RoundButton(
                        icon: Icons.ios_share,
                        tooltip: _t('Wadaag sawir', 'Share a photo'),
                        onVideo: onVideo,
                        onTap: canAttach ? _pickPhoto : null,
                      ),
                      GestureDetector(
                        onTap: _interrupt,
                        child: AnimatedBuilder(
                          animation: _clock,
                          builder: (_, _) => _LivePill(level: muted ? 0 : _level),
                        ),
                      ),
                      _RoundButton(
                        icon: muted ? Icons.mic_off : Icons.mic_none,
                        tooltip: _t('Makarafoonka', 'Microphone'),
                        active: muted,
                        onVideo: onVideo,
                        onTap: _toggleMute,
                      ),
                      // End the call: red, like a phone call.
                      _RoundButton(
                        icon: Icons.close,
                        tooltip: strings.close,
                        onVideo: onVideo,
                        danger: true,
                        onTap: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A 46 px round button: light grey with a dark icon on the white page, white glass over the
/// camera. [active] = Garad purple with a white icon (camera on, mic off); [danger] = red (end call).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.onVideo,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool onVideo;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final (background, foreground, border) = switch ((active, danger, onVideo)) {
      (true, _, _) => (c.brand, Colors.white, Colors.transparent),
      (_, true, _) => (const Color(0xFFE5484D), Colors.white, Colors.transparent),
      (_, _, true) => (const Color(0x33FFFFFF), Colors.white, const Color(0x22FFFFFF)),
      _ => (c.surfaceStrong, c.text, c.line),
    };
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: CircleBorder(side: BorderSide(color: border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 46,
            child: Icon(icon, color: onTap == null ? foreground.withValues(alpha: 0.35) : foreground, size: 21),
          ),
        ),
      ),
    );
  }
}

/// The centre pill: white, with a Garad-purple glow and inner gradient that follow the voices.
class _LivePill extends StatelessWidget {
  const _LivePill({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final glow = level.clamp(0.0, 1.0);
    return Container(
      width: 112,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color.lerp(c.brandSoft, c.brand, 0.15 + glow * 0.55)!],
        ),
        border: Border.all(color: c.brand.withValues(alpha: 0.18 + glow * 0.3)),
        boxShadow: [
          BoxShadow(
            color: c.brand.withValues(alpha: 0.18 + glow * 0.4),
            blurRadius: 14 + glow * 26,
            spreadRadius: glow * 4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
    );
  }
}

/// A soft Garad-purple glow rising from the bottom of the screen; [level] 0..1 lifts and brightens it.
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.level, required this.color, required this.onVideo});

  final double level;
  final Color color;
  final bool onVideo;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = level.clamp(0.0, 1.0);
    final height = size.height * (0.30 + glow * 0.16);
    final rect = Rect.fromLTWH(-size.width * 0.25, size.height - height, size.width * 1.5, height * 2);
    // Gentler on the white page than over video, so the screen stays light.
    final strength = onVideo ? 0.55 : 0.45;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: (0.45 + glow * 0.35) * strength),
            color.withValues(alpha: (0.22 + glow * 0.18) * strength),
            color.withValues(alpha: 0.06 * strength),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.level != level || old.color != color || old.onVideo != onVideo;
}

/// Captions off: Garad's orb in the middle — a white circle with the animated Garad logo, glowing
/// and growing a little with the voices.
class _Orb extends StatelessWidget {
  const _Orb({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final glow = level.clamp(0.0, 1.0);
    final size = 132 + glow * 28;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [Colors.white, Color.lerp(c.brandSoft, c.brand, 0.1 + glow * 0.35)!]),
        boxShadow: [
          BoxShadow(
            color: c.brand.withValues(alpha: 0.18 + glow * 0.35),
            blurRadius: 30 + glow * 30,
            spreadRadius: 2 + glow * 8,
          ),
        ],
      ),
      child: const GaradThinkingLogo(size: 56),
    );
  }
}
