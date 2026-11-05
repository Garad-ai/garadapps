import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../api/models.dart';
import '../chat_strings.dart';
import '../strings.dart';

/// The answer to one spoken turn: the reply text, or a failure (with an optional message).
class VoiceReply {
  const VoiceReply(this.text) : error = null;
  const VoiceReply.failed(this.error) : text = null;

  final String? text;
  final String? error;
}

enum _Phase { starting, listening, thinking, speaking, paused, unavailable }

/// Voice mode: a hands-free conversation with Garad around an animated orb.
/// listen → (user stops talking) → ask Garad → speak the answer → listen again, until the user ends.
/// Tap the orb to interrupt Garad; the mic button pauses / resumes; ✕ ends.
class VoiceModeScreen extends StatefulWidget {
  const VoiceModeScreen({
    super.key,
    required this.ask,
    required this.cancel,
    this.userName = '',
    this.models = const [],
    this.modelId,
    this.onModelChanged,
    this.onNewChat,
  });

  /// Sends what the user said through the chat (so it is saved) and returns Garad's answer.
  final Future<VoiceReply> Function(String text) ask;

  /// Stops waiting for an answer (when the user interrupts while Garad is thinking).
  final VoidCallback cancel;

  /// For "Let's talk, Amina".
  final String userName;

  /// The AI models to choose from (the pill at the bottom) and the one in use.
  final List<ChatModelInfo> models;
  final String? modelId;
  final ValueChanged<String>? onModelChanged;

  /// ＋ : start a new chat (voice continues in it).
  final VoidCallback? onNewChat;

  @override
  State<VoiceModeScreen> createState() => _VoiceModeScreenState();
}

class _VoiceModeScreenState extends State<VoiceModeScreen> with SingleTickerProviderStateMixin {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  final _random = math.Random();

  late final AnimationController _clock;

  _Phase _phase = _Phase.starting;
  String _heard = '';
  String _reply = '';
  String? _error;
  bool _gotFinal = false;
  int _turn = 0;

  /// 🔊 off: answers are shown, not spoken.
  bool _speaker = true;

  /// Speaking speed: 0.8 slow, 1 normal, 1.25 fast.
  double _speed = 1;
  String? _modelId;

  /// The last answer, kept on screen while listening again when the speaker is off.
  String _lastReply = '';

  /// Orb energy 0..1: follows the microphone while listening, each spoken word while speaking.
  double _level = 0;
  double _target = 0;
  DateTime _lastBump = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..addListener(_tick)
      ..repeat();
    _tts.setCompletionHandler(_onSpokenDone);
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((_) => _onSpokenDone());
    // Each word Garad speaks gives the orb a pulse.
    _tts.setProgressHandler((text, start, end, word) => _bump(0.55 + _random.nextDouble() * 0.45));
    _modelId = widget.modelId;
    _applySpeed();
    _start();
  }

  @override
  void dispose() {
    _clock.dispose();
    _stt.cancel();
    _tts.stop();
    super.dispose();
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
        target = 0.12 + 0.06 * math.sin(now.millisecondsSinceEpoch / 260);
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
    final ok = await _stt.initialize(
      onStatus: (status) {
        // The recogniser stopped without hearing a full sentence: listen again.
        if ((status == 'done' || status == 'notListening') && _phase == _Phase.listening && !_gotFinal) {
          final turn = _turn;
          Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted && _phase == _Phase.listening && turn == _turn && !_stt.isListening) _listen();
          });
        }
      },
      onError: (_) {
        if (mounted && _phase == _Phase.listening) {
          final turn = _turn;
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted && _phase == _Phase.listening && turn == _turn) _listen();
          });
        }
      },
    );
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
    await _tts.stop();
    _turn++;
    setState(() {
      _phase = _Phase.listening;
      _heard = '';
      _error = null;
      _gotFinal = false;
    });

    // Somali recognition for Somali users when the phone has it; otherwise the phone's default.
    String? localeId;
    if (chatStrings.isSomali) {
      final locales = await _stt.locales();
      localeId = locales.where((l) => l.localeId.toLowerCase().startsWith('so')).firstOrNull?.localeId;
    }
    if (!mounted || _phase != _Phase.listening) return;

    await _stt.listen(
      onResult: (result) {
        if (!mounted || _phase != _Phase.listening) return;
        final words = result.recognizedWords;
        // Browsers give no sound level: let new words move the orb instead.
        if (words.length > _heard.length) _bump(0.4 + _random.nextDouble() * 0.3);
        setState(() => _heard = words);
        if (result.finalResult && words.trim().isNotEmpty) {
          _gotFinal = true;
          _ask(words.trim());
        }
      },
      // Android reports about -2..10 dB; iOS a similar range. Map it to 0..1.
      onSoundLevelChange: (level) => _bump(((level + 2) / 12).clamp(0.0, 1.0)),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 60),
      ),
    );
  }

  Future<void> _ask(String text) async {
    await _stt.stop();
    if (!mounted) return;
    final turn = ++_turn;
    setState(() {
      _phase = _Phase.thinking;
      _reply = '';
    });

    final reply = await widget.ask(text);
    if (!mounted || turn != _turn) return; // interrupted meanwhile

    final answer = reply.text;
    if (answer == null || answer.trim().isEmpty) {
      setState(() => _error = reply.error ?? chatStrings.somethingWrong);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (mounted && turn == _turn) _listen();
      return;
    }

    _lastReply = answer;
    if (!_speaker) {
      // Speaker off: show the answer and keep listening.
      await _listen();
      return;
    }
    setState(() {
      _phase = _Phase.speaking;
      _reply = answer;
    });
    _lastBump = DateTime.now();
    await _tts.speak(_speakable(answer));
  }

  Future<void> _applySpeed() async {
    // Normal speed is 0.5 for the phone voices and 1.0 for the browser's.
    final normal = kIsWeb ? 1.0 : 0.5;
    await _tts.setSpeechRate((normal * _speed).clamp(0.1, kIsWeb ? 2.0 : 1.0));
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speaker = !_speaker);
    if (!_speaker && _phase == _Phase.speaking) {
      await _tts.stop();
      await _listen();
    }
  }

  Future<void> _pickModel() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF262624),
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in widget.models)
              ListTile(
                title: Text(m.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  m.description ?? m.provider,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: m.id == _modelId ? const Icon(Icons.check, color: Colors.white) : null,
                onTap: () => Navigator.pop(sheet, m.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _modelId = picked);
    widget.onModelChanged?.call(picked);
  }

  Future<void> _settings() async {
    final so = chatStrings.isSomali;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF262624),
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  so ? 'Xawaaraha hadalka' : 'Speaking speed',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SegmentedButton<double>(
                  segments: [
                    ButtonSegment(value: 0.8, label: Text(so ? 'Tartiib' : 'Slow')),
                    ButtonSegment(value: 1.0, label: Text(so ? 'Caadi' : 'Normal')),
                    ButtonSegment(value: 1.25, label: Text(so ? 'Degdeg' : 'Fast')),
                  ],
                  selected: {_speed},
                  style: SegmentedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    selectedForegroundColor: const Color(0xFF1E1E1C),
                    selectedBackgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onSelectionChanged: (value) {
                    setState(() => _speed = value.first);
                    setSheet(() {});
                    _applySpeed();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onSpokenDone() {
    if (mounted && _phase == _Phase.speaking) _listen();
  }

  /// Tap on the orb: stop Garad (speaking or thinking) and listen; or start listening when paused.
  Future<void> _interrupt() async {
    switch (_phase) {
      case _Phase.speaking:
        await _tts.stop();
        await _listen();
      case _Phase.thinking:
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

  Future<void> _togglePause() async {
    if (_phase == _Phase.paused) {
      await _listen();
      return;
    }
    _turn++;
    await _stt.stop();
    await _tts.stop();
    if (_phase == _Phase.thinking) widget.cancel();
    if (mounted) setState(() => _phase = _Phase.paused);
  }

  /// Words to say, not Markdown symbols or code.
  static String _speakable(String markdown) => markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'[*_`#>|~]'), '')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
      .trim();

  // ---- UI ----

  String get _status {
    final so = chatStrings.isSomali;
    return switch (_phase) {
      _Phase.starting => '',
      _Phase.listening => chatStrings.listening,
      _Phase.thinking => so ? 'Waan ka fekerayaa…' : 'Thinking…',
      _Phase.speaking => so ? 'Taabo si aad u joojiso' : 'Tap to interrupt',
      _Phase.paused => so ? 'Hakad — taabo makarafoonka' : 'Paused — tap the mic to continue',
      _Phase.unavailable => _error ?? chatStrings.micUnavailable,
    };
  }

  String get _caption {
    if (_error != null) return _error!;
    if (_phase == _Phase.speaking) return _reply.length > 260 ? '…${_reply.substring(_reply.length - 260)}' : _reply;
    if (_phase == _Phase.thinking) return _heard;
    if (_phase == _Phase.listening) {
      // Before the user speaks again, keep the last answer readable (speaker off, or a quick glance).
      if (_heard.isNotEmpty) return _heard;
      return _lastReply.length > 260 ? '…${_lastReply.substring(_lastReply.length - 260)}' : _lastReply;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF1E1E1C);
    final so = chatStrings.isSomali;
    final first = widget.userName.trim().split(RegExp(r'\s+')).first;
    final greeting = so
        ? (first.isEmpty ? 'Aan wada hadalno' : 'Aan wada hadalno, $first')
        : (first.isEmpty ? "Let's talk" : "Let's talk, $first");
    final model = widget.models.where((m) => m.id == _modelId).firstOrNull;
    final orbOnStage = _phase == _Phase.speaking || _phase == _Phase.thinking;

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          // Soft blue glow from the bottom; it rises with your voice and Garad's.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _clock,
              builder: (_, _) {
                final glow = _phase == _Phase.paused || _phase == _Phase.unavailable ? 0.0 : _level;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 1.35),
                      radius: 0.85 + glow * 0.45,
                      colors: [
                        const Color(0xFF5B7BD6).withValues(alpha: 0.42 + glow * 0.35),
                        const Color(0xFF3B4F8F).withValues(alpha: 0.18 + glow * 0.15),
                        background.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ☰ back to the chat · ⚙ settings
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _CircleButton(
                        icon: Icons.notes_rounded,
                        tooltip: strings.close,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      _CircleButton(icon: Icons.settings_outlined, tooltip: chatStrings.settings, onTap: _settings),
                    ],
                  ),
                ),
                const Spacer(),
                // Centre: logo + "Let's talk" while listening; the orb while Garad thinks or speaks.
                GestureDetector(
                  onTap: _interrupt,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: orbOnStage
                        ? LayoutBuilder(
                            key: const ValueKey('orb'),
                            builder: (context, constraints) {
                              final height = MediaQuery.sizeOf(context).height;
                              final size = [constraints.maxWidth * 0.55, height * 0.28, 230.0].reduce(math.min);
                              return SizedBox.square(
                                dimension: size * 1.3,
                                child: AnimatedBuilder(
                                  animation: _clock,
                                  builder: (_, _) => CustomPaint(
                                    painter: _OrbPainter(
                                      time: DateTime.now().millisecondsSinceEpoch / 1000,
                                      level: _level,
                                      thinking: _phase == _Phase.thinking,
                                      dim: false,
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : Column(
                            key: const ValueKey('greeting'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset('assets/images/splash-icon.png', height: 38, semanticLabel: 'Garad AI'),
                              const SizedBox(height: 14),
                              Text(
                                greeting,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'serif',
                                  fontFamilyFallback: ['Georgia', 'Times New Roman', 'Noto Serif'],
                                  color: Colors.white,
                                  fontSize: 24,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 13.5)),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: SizedBox(
                    height: 92,
                    child: Text(
                      _caption,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _error != null ? const Color(0xFFFCA5A5) : Colors.white,
                        fontSize: 16.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Big 🎤: pause / resume listening, or interrupt Garad.
                AnimatedBuilder(
                  animation: _clock,
                  builder: (_, _) {
                    final paused = _phase == _Phase.paused || _phase == _Phase.unavailable;
                    final ring = _phase == _Phase.listening ? 6 + _level * 14 : 0.0;
                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (ring > 0)
                            BoxShadow(
                              color: const Color(0xFF8FA8FF).withValues(alpha: 0.35),
                              blurRadius: ring,
                              spreadRadius: ring / 3,
                            ),
                        ],
                      ),
                      child: Material(
                        color: paused ? Colors.white : const Color(0xFF3A4566),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: switch (_phase) {
                            _Phase.speaking || _Phase.thinking => _interrupt,
                            _Phase.unavailable => _start,
                            _ => _togglePause,
                          },
                          child: SizedBox.square(
                            dimension: 66,
                            child: Icon(
                              paused ? Icons.mic_off_outlined : Icons.mic_none_rounded,
                              color: paused ? background : Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                // ＋ new chat · model · 🔊 speaker · ✕ end
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Row(
                    children: [
                      _CircleButton(
                        icon: Icons.add,
                        tooltip: chatStrings.newChat,
                        onTap: widget.onNewChat == null
                            ? null
                            : () {
                                widget.onNewChat!();
                                setState(() {
                                  _lastReply = '';
                                  _heard = '';
                                });
                              },
                      ),
                      const SizedBox(width: 8),
                      if (widget.models.isNotEmpty)
                        Flexible(
                          child: Material(
                            color: const Color(0x33FFFFFF),
                            shape: const StadiumBorder(),
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: _pickModel,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        model?.name ?? chatStrings.model,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.unfold_more, color: Colors.white70, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      _CircleButton(
                        icon: _speaker ? Icons.volume_up_outlined : Icons.volume_off_outlined,
                        tooltip: chatStrings.readAloud,
                        onTap: _toggleSpeaker,
                      ),
                      const SizedBox(width: 10),
                      _CircleButton(
                        icon: Icons.close,
                        tooltip: strings.close,
                        light: true,
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

/// A 44 px round button on the voice screen; [light] = white with a dark icon (✕).
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.tooltip, required this.onTap, this.light = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool light;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: light ? Colors.white : const Color(0x33FFFFFF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Icon(icon, color: light ? const Color(0xFF1E1E1C) : Colors.white, size: 21),
        ),
      ),
    ),
  );
}

/// The glowing orb: a deep blue-violet sphere with luminous waves inside.
/// [level] (0..1) sets how much the waves move; [thinking] makes it breathe slowly.
class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.time, required this.level, required this.thinking, required this.dim});

  final double time;
  final double level;
  final bool thinking;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final breathe = thinking ? 1 + 0.035 * math.sin(time * 2.4) : 1 + level * 0.05;
    final r = size.shortestSide / 1.3 / 2 * breathe;
    final energy = dim ? 0.0 : level.clamp(0.0, 1.0);

    // 1. Halo around the sphere.
    canvas.drawCircle(
      center,
      r * 1.08,
      Paint()
        ..color = const Color(0xFF5B5BFF).withValues(alpha: dim ? 0.12 : 0.28 + energy * 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.32),
    );

    // 2. The sphere.
    final sphere = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.35),
          radius: 1.05,
          colors: [Color(0xFF4F4BF0), Color(0xFF2B25B0), Color(0xFF15115A), Color(0xFF08071F)],
          stops: [0.0, 0.42, 0.78, 1.0],
        ).createShader(sphere),
    );

    // 3. Waves inside the sphere.
    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));
    final waves = [
      (color: const Color(0xFF67E8F9), amp: 1.0, freq: 1.5, speed: 1.0, width: 3.2),
      (color: const Color(0xFFC084FC), amp: 0.75, freq: 2.3, speed: -1.35, width: 2.6),
      (color: const Color(0xFF818CF8), amp: 0.55, freq: 3.1, speed: 0.8, width: 2.2),
      (color: Colors.white, amp: 0.45, freq: 1.9, speed: 1.6, width: 1.6),
    ];
    final baseAmp = r * (0.035 + energy * 0.36);
    for (var i = 0; i < waves.length; i++) {
      final w = waves[i];
      final phase = time * math.pi * w.speed + i * 1.3;
      final path = Path();
      for (var x = -r; x <= r; x += 2) {
        final u = x / r; // -1..1
        final envelope = math.pow(math.cos(u * math.pi / 2), 2).toDouble();
        final y = center.dy + baseAmp * w.amp * envelope * math.sin(w.freq * u * math.pi + phase);
        x == -r ? path.moveTo(center.dx + x, y) : path.lineTo(center.dx + x, y);
      }
      final alpha = dim ? 0.25 : 0.55 + energy * 0.45;
      // Soft haze, then a glowing line.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w.width * 5
          ..color = w.color.withValues(alpha: alpha * 0.25)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w.width
          ..strokeCap = StrokeCap.round
          ..color = w.color.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
    // Bright core where the waves cross.
    canvas.drawCircle(
      center,
      r * (0.08 + energy * 0.12),
      Paint()
        ..color = Colors.white.withValues(alpha: dim ? 0.05 : 0.18 + energy * 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
    );
    canvas.restore();

    // 4. Glassy rim and highlight.
    canvas.drawCircle(
      center,
      r - 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.2),
            Colors.white.withValues(alpha: 0.35),
          ],
        ).createShader(sphere),
    );
    canvas.drawCircle(
      center + Offset(-r * 0.35, -r * 0.45),
      r * 0.22,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}
