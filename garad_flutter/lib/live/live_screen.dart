import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../app_storage.dart';
import '../browser_color.dart';
import '../chat_strings.dart';
import 'live_call.dart';

/// Garad Live: talk with Garad like a phone call, and show it the world with the camera.
/// No buttons to press while talking: Garad listens all the time and stops when you speak.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.getKey, required this.userName});

  final Future<LiveKey> Function() getKey;
  final String userName;

  /// Opens the older voice mode when Garad Live cannot start (e.g. not set up on the server).
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with SingleTickerProviderStateMixin {
  late final LiveCall _call = LiveCall(getKey: widget.getKey)..takeFrame = _takeFrame;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _cameraBusy = false;
  bool _switchingCamera = false; // between closing one camera and opening the other
  Offset? _focusPoint;
  String? _startError;
  String? _startDetail;
  bool _noCredits = false; // out of credits: "Try again" would not help

  static String _t(String so, String en) => chatStrings.isSomali ? so : en;

  @override
  void initState() {
    super.initState();
    _call.addListener(_changed);
    _loadCaptions();
    _start();
  }

  Future<void> _start() async {
    // A failed connection to OpenAI is often a one-off (a slow network or a busy server):
    // try once more by itself before showing an error.
    for (var attempt = 1; ; attempt++) {
      try {
        await _call.start();
        return;
      } on ApiException catch (e) {
        if (mounted) {
          setState(() {
            _startError = e.message;
            _noCredits = e.statusCode == 402;
          });
        }
        return;
      } on LiveException catch (e) {
        debugPrint('Garad Live could not start: $e');
        if (e.reason == 'microphone') {
          if (mounted) {
            setState(() => _startError = _t(
              'Garad wuxuu u baahan yahay makarafoonka. Ka oggolow Settings, kadibna isku day mar kale.',
              'Garad needs the microphone. Allow it in Settings, then try again.',
            ));
          }
          return;
        }
        if (e.reason == 'busy') {
          // The AI service refused (account limit): retrying now would not help, and it is not the internet.
          if (mounted) {
            setState(() {
              _startError = _t(
                'Garad Live hadda lama heli karo. Fadlan isku day mar dambe.',
                'Garad Live is not available right now. Please try again later.',
              );
              _startDetail = e.detail;
            });
          }
          return;
        }
        if (attempt >= 2 || !mounted) return _couldNotConnect(e.toString());
      } catch (e) {
        debugPrint('Garad Live could not start: $e');
        if (attempt >= 2 || !mounted) return _couldNotConnect(e.toString());
      }
      await _call.reset();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
    }
  }

  /// [detail]: the exact reason, shown small under the message so a screenshot tells us the cause.
  void _couldNotConnect(String detail) {
    if (!mounted) return;
    setState(() {
      _startError = _t(
        'Garad Live kuma xidhmi karo hadda. Hubi internetka, kadibna isku day mar kale.',
        'Garad Live could not connect. Check your internet, then try again.',
      );
      _startDetail = detail.length > 200 ? detail.substring(0, 200) : detail;
    });
  }

  /// "Try again" after a failure: a fresh call on the same screen.
  Future<void> _retry() async {
    await _call.reset();
    if (!mounted) return;
    setState(() {
      _startError = null;
      _startDetail = null;
      _noCredits = false;
    });
    _start();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _call.removeListener(_changed);
    _call.hangUp();
    _camera?.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ---- Camera ----

  Future<void> _toggleCamera() async {
    if (_cameraBusy) return;
    if (_camera != null) {
      final old = _camera;
      setState(() => _camera = null);
      await old?.dispose();
      return;
    }
    _cameraBusy = true;
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('none', 'No camera');
      final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _cameraIndex = back < 0 ? 0 : back;
      await _openCamera();
      // Like Gemini Live: Garad says what it sees as soon as the camera is on.
      await Future<void>.delayed(const Duration(milliseconds: 600)); // exposure settles
      final frame = await _takeFrame();
      if (frame != null) _call.cameraOpened(frame);
    } catch (e) {
      debugPrint('Garad Live camera: $e');
      _flash(_t('Kamaradda lama heli karo. Hubi oggolaanshaha.', 'The camera is not available. Check the permission.'));
    } finally {
      _cameraBusy = false;
    }
  }

  Future<void> _openCamera() async {
    // Close the old camera first. On Android, closing a camera stops every camera, so closing
    // the old one after opening the new one left the new one dead (the flip did nothing).
    final old = _camera;
    if (old != null) {
      setState(() => _camera = null);
      await old.dispose();
    }
    final controller = CameraController(
      _cameras[_cameraIndex],
      // Full HD: the preview stays sharp; pictures for Garad are made smaller before sending.
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _camera = controller;
      _focusPoint = null;
    });
  }

  Future<void> _flipCamera() async {
    if (_cameraBusy) return;
    _cameraBusy = true;
    try {
      // Browsers list only one camera until camera access is allowed: ask again now that it is.
      if (_cameras.length < 2) _cameras = await availableCameras();
      final current = _camera?.description.lensDirection;
      // The camera facing the other way (front ↔ back); otherwise simply the next one.
      final other = _cameras.indexWhere((c) => c.lensDirection != current && c.lensDirection != CameraLensDirection.external);
      if (other < 0 && _cameras.length < 2) {
        _flash(_t('Kamarad kale lama helin.', 'No other camera found.'));
        return;
      }
      _cameraIndex = other >= 0 ? other : (_cameraIndex + 1) % _cameras.length;
      setState(() => _switchingCamera = true);
      await _openCamera();
    } catch (e) {
      debugPrint('Garad Live flip: $e');
      _flash(_t('Kamaradda lama beddeli karo.', 'Could not switch the camera.'));
    } finally {
      _cameraBusy = false;
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _focusAt(Offset point) async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    final p = Offset(point.dx.clamp(0.0, 1.0), point.dy.clamp(0.0, 1.0));
    setState(() => _focusPoint = p);
    try {
      await Future.wait([camera.setFocusPoint(p), camera.setExposurePoint(p)]);
    } catch (_) {}
  }

  /// What the camera sees now, small enough to send; null when the camera is off.
  Future<Uint8List?> _takeFrame() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || camera.value.isTakingPicture) return null;
    try {
      final point = _focusPoint ?? const Offset(0.5, 0.5);
      try {
        await Future.wait([camera.setFocusPoint(point), camera.setExposurePoint(point)]);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } catch (_) {}
      final bytes = await (await camera.takePicture()).readAsBytes();
      return await shrinkFrame(bytes);
    } catch (e) {
      debugPrint('Garad Live frame: $e');
      return null;
    }
  }

  void _flash(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- Screen ----

  static double _shortSide(Size? size) => size == null ? 1080 : math.min(size.width, size.height);
  static double _longSide(Size? size) => size == null ? 1920 : math.max(size.width, size.height);

  /// Captions are off unless the user turns them on; the choice is kept on this phone.
  bool _captions = false;
  static const _captionsKey = 'garad_live_captions';

  Future<void> _loadCaptions() async {
    try {
      final saved = await const AppStorage().read(key: _captionsKey);
      if (mounted && saved == '1') setState(() => _captions = true);
    } catch (_) {}
  }

  void _toggleCaptions() {
    setState(() => _captions = !_captions);
    const AppStorage().write(key: _captionsKey, value: _captions ? '1' : '0').catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    setBrowserColor(Colors.black);
    final camera = _camera;
    final onVideo = camera != null && camera.value.isInitialized;
    final name = widget.userName.trim().split(' ').first;
    final failed = _startError != null || _call.state == LiveState.ended && _call.error != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Garad's voice in a browser (an invisible player; phones play it by themselves).
          if (kIsWeb) Offstage(child: SizedBox(width: 1, height: 1, child: RTCVideoView(_call.voice))),

          if (onVideo)
            LayoutBuilder(
              builder: (context, box) => GestureDetector(
                onTapUp: (d) => _focusAt(Offset(d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight)),
                // The camera's own picture size (portrait), scaled to fill the screen — not zoomed in.
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  // Upright: the short side across, the long side down. Phones report the size sideways
                  // (1920×1080) and browsers upright (1080×1920); swapping blindly zoomed a browser in.
                  child: SizedBox(
                    width: _shortSide(camera.value.previewSize),
                    height: _longSide(camera.value.previewSize),
                    // The front camera shows like a mirror (your right hand on the right), as in Gemini Live.
                    // The pictures Garad gets are the right way round, so it can still read held-up text.
                    child: CameraPreview(camera),
                  ),
                ),
              ),
            )
          else if (!_switchingCamera)
            Center(child: _Orb(state: _call.state, pulse: _pulse)),

          // Shade behind the captions and buttons so white text reads on any picture.
          if (onVideo)
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x66000000), Color(0x00000000), Color(0x00000000), Color(0xAA000000)],
                    stops: [0, 0.18, 0.5, 1],
                  ),
                ),
              ),
            ),

          SafeArea(
            child: Column(
              children: [
                // Top right, like Gemini Live: flip the camera (while it is on) and captions on or off
                // (off unless the user turns them on).
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onVideo) ...[
                        _TopButton(icon: Icons.cameraswitch_outlined, tooltip: _t('Beddel kamaradda', 'Flip camera'), onTap: _flipCamera),
                        const SizedBox(width: 10),
                      ],
                      _TopButton(
                        icon: _captions ? Icons.closed_caption : Icons.closed_caption_off_outlined,
                        active: _captions,
                        tooltip: _captions ? _t('Qari qoraalka', 'Hide captions') : _t('Muuji qoraalka', 'Show captions'),
                        onTap: _toggleCaptions,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: failed ? _failure() : _captionArea(name, onVideo),
                ),                const SizedBox(height: 20),
                _controls(onVideo),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _captionArea(String name, bool onVideo) {
    final garad = _call.garadText.trim();
    final user = _call.userText.trim();
    final started = garad.isNotEmpty || user.isNotEmpty;
    // Before anyone has spoken: a quiet welcome over the orb (none over the camera picture).
    if (!started) {
      if (onVideo) return const SizedBox.shrink();
      return Text(
        name.isEmpty ? _t('Aan wada hadalno', "Let's talk") : _t('Aan wada hadalno, $name', "Let's talk, $name"),
        style: const TextStyle(color: Colors.white, fontSize: 26, fontFamily: 'SourceSerif'),
      );
    }
    if (!_captions) return const SizedBox.shrink();
    // Captions, like Gemini Live: the latest words in a soft rounded box (Garad's while it talks).
    final text = garad.isNotEmpty && _call.state != LiveState.userSpeaking ? garad : user;
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xCC303134),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 120),
        child: SingleChildScrollView(
          reverse: true, // the newest words stay in view
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.35)),
        ),
      ),
    );
  }

  Widget _failure() {
    final message = _startError ??
        _t('Xidhiidhku wuu go\'ay. Dib u bilow wicitaanka.', 'The connection was lost. Start the call again.');
    return Column(
      children: [
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
        if (_startDetail case final detail?) ...[
          const SizedBox(height: 6),
          Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
        ],
        if (!_noCredits) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _retry,
            child: Text(_t('Isku day mar kale', 'Try again'), style: const TextStyle(color: Color(0xFF9DA2FF))),
          ),
        ],
      ],
    );
  }

  Widget _controls(bool onVideo) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: onVideo ? Icons.videocam : Icons.videocam_outlined,
          active: onVideo,
          tooltip: _t('Kamarad', 'Camera'),
          onTap: _toggleCamera,
        ),
        _RoundButton(
          icon: _call.muted ? Icons.mic_off : Icons.mic_none,
          active: _call.muted,
          tooltip: _call.muted ? _t('Fur makarafoonka', 'Unmute') : _t('Dami makarafoonka', 'Mute'),
          onTap: () => _call.setMuted(!_call.muted),
        ),
        // Loudspeaker on/off. Off = the earbuds when connected, otherwise the earpiece.
        if (!kIsWeb)
          _RoundButton(
            icon: _call.speakerOn
                ? Icons.volume_up
                : (_call.headset ? Icons.headphones : Icons.phone_in_talk_outlined),
            active: _call.speakerOn,
            tooltip: _call.speakerOn
                ? _t('Dami sameecadda', 'Speaker off')
                : _t('Shid sameecadda', 'Speaker on'),
            onTap: _call.toggleSpeaker,
          ),
        _RoundButton(
          icon: Icons.close,
          color: const Color(0xFFE5484D),
          tooltip: _t('Dhammee', 'End'),
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.tooltip, this.active = false, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final background = color ?? (active ? Colors.white : const Color(0x33FFFFFF));
    final foreground = color != null ? Colors.white : (active ? Colors.black : Colors.white);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 60, height: 60, child: Icon(icon, color: foreground, size: 26)),
        ),
      ),
    );
  }
}

/// A small round button at the top (captions), like Gemini Live's.
class _TopButton extends StatelessWidget {
  const _TopButton({required this.icon, required this.onTap, required this.tooltip, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? const Color(0x55FFFFFF) : const Color(0x26FFFFFF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 22)),
        ),
      ),
    );
  }
}

/// Garad's orb (the blue sphere with light waves) when the camera is off. It breathes gently
/// while listening, swells and glows with Garad's voice, and turns slowly while it thinks.
class _Orb extends StatelessWidget {
  const _Orb({required this.state, required this.pulse});

  final LiveState state;
  final Animation<double> pulse;

  static const _image = AssetImage('assets/images/live_orb.png');

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final t = pulse.value * 2 * math.pi;
        final (amount, speed, glow) = switch (state) {
          LiveState.speaking => (0.10, 2.0, 0.55),
          LiveState.userSpeaking => (0.05, 1.0, 0.40),
          LiveState.thinking => (0.03, 3.0, 0.35),
          _ => (0.025, 1.0, 0.28),
        };
        // Speaking: an uneven swell, like a voice, not a metronome.
        final beat = state == LiveState.speaking ? (math.sin(t * speed) + 0.5 * math.sin(t * speed * 2.7)) / 1.5 : math.sin(t * speed);
        final scale = 1 + amount * beat;
        final turn = state == LiveState.thinking ? pulse.value * 2 * math.pi : 0.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4B4FE0).withValues(alpha: glow + 0.1 * beat.abs()),
                  blurRadius: 70,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: Transform.rotate(angle: turn, child: const Image(image: _image, fit: BoxFit.contain)),
          ),
        );
      },
    );
  }
}
