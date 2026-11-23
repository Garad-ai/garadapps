import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../api/models.dart';

/// What Garad Live is doing right now.
enum LiveState { connecting, listening, userSpeaking, thinking, speaking, ended }

/// Garad Live: one live voice conversation with OpenAI's realtime model, like Gemini Live.
///
/// The microphone streams to OpenAI and Garad's voice streams back while it is being made (WebRTC),
/// so it starts talking about a second after the user stops. Garad listens the whole time: when the
/// user starts talking, OpenAI stops Garad's voice by itself (server voice detection with
/// interrupt_response) — there is no interrupt button. With the camera on, a fresh picture goes in
/// with every turn, and Garad greets the user and says what it sees when the camera is turned on.
class LiveCall extends ChangeNotifier {
  LiveCall({required this.getKey});

  /// A short-lived key from the Garad server (the real OpenAI key never reaches the phone).
  final Future<LiveKey> Function() getKey;

  /// Takes a picture of what the camera sees (already small enough to send), or null when the
  /// camera is off. Called when the user starts talking, so the picture is ready when they stop.
  Future<Uint8List?> Function()? takeFrame;

  /// Plays Garad's voice in a browser. Phones play it through the call's audio by themselves.
  final RTCVideoRenderer voice = RTCVideoRenderer();

  LiveState state = LiveState.connecting;

  /// What the user just said, and what Garad is saying (live captions).
  String userText = '';
  String garadText = '';

  /// Why the call stopped working, for the screen to show.
  String? error;

  bool muted = false;

  /// Garad's voice on the loudspeaker (true) or in earbuds / the earpiece (false).
  bool speakerOn = true;

  /// Bluetooth earbuds or a wired headset are connected.
  bool headset = false;

  /// The user picked the loudspeaker while earbuds were connected: keep it until they change it.
  bool _speakerChosen = false;
  bool _routed = false;

  RTCPeerConnection? _pc;
  MediaStream? _mic;
  RTCDataChannel? _events;
  Future<Uint8List?>? _frame;
  bool _closed = false;
  bool _voiceReady = false;

  /// Starts the call. Throws when it cannot (the screen shows why).
  Future<void> start() async {
    final key = await getKey();
    // Android 12+: without "Nearby devices" the app cannot see Bluetooth earbuds (the voice would
    // stay on the loudspeaker). Asked once; refusing it only means no earbuds.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await Permission.bluetoothConnect.request();
      } catch (_) {}
    }
    if (_closed) return;
    if (!_voiceReady) {
      await voice.initialize();
      _voiceReady = true;
    }

    final pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
    _pc = pc;
    pc.onTrack = (event) {
      if (event.track.kind == 'audio' && event.streams.isNotEmpty) voice.srcObject = event.streams.first;
    };
    pc.onConnectionState = (s) {
      // "Disconnected" often recovers by itself on a phone (a short Wi-Fi drop); only "failed" is final.
      if (_pc == pc && s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) _fail('lost');
    };

    // The phone's own echo cancelling keeps Garad from hearing (and interrupting) itself.
    final MediaStream mic;
    try {
      mic = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': false,
      });
    } catch (e) {
      debugPrint('Garad Live microphone: $e');
      throw const LiveException('microphone');
    }
    _mic = mic;
    for (final track in mic.getAudioTracks()) {
      await pc.addTrack(track, mic);
    }

    final events = await pc.createDataChannel('oai-events', RTCDataChannelInit());
    _events = events;
    events.onMessage = (message) => _onEvent(message.text);
    events.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) _onOpen();
    };

    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    final answer = await http
        .post(
          Uri.parse('https://api.openai.com/v1/realtime/calls'),
          headers: {'Authorization': 'Bearer ${key.key}', 'Content-Type': 'application/sdp'},
          body: utf8.encode(offer.sdp ?? ''),
        )
        .timeout(const Duration(seconds: 20));
    if (answer.statusCode >= 300) {
      debugPrint('Garad Live: OpenAI refused the call (${answer.statusCode}): ${answer.body}');
      final body = answer.body.length > 160 ? answer.body.substring(0, 160) : answer.body;
      // 429 = OpenAI's account has no money left or is over its limit: not the user's internet.
      if (answer.statusCode == 429) throw LiveException('busy', 'OpenAI 429: $body');
      throw LiveException('refused', 'OpenAI ${answer.statusCode}: $body');
    }
    if (_closed) return;
    await pc.setRemoteDescription(RTCSessionDescription(answer.body, 'answer'));
    // Phones: Garad's voice in the earbuds when they are connected, otherwise on the loudspeaker;
    // and it follows earbuds connected or taken out during the call.
    if (!kIsWeb) {
      navigator.mediaDevices.ondevicechange = (_) => _routeAudio();
      await _routeAudio();
    }
  }

  /// Connected: Garad stays quiet and listens (no greeting), like Gemini Live.
  void _onOpen() => _set(LiveState.listening);

  /// The camera was just turned on: Garad says hello and what it sees, like Gemini Live.
  void cameraOpened(Uint8List frame) {
    _stopSpeaking();
    _sendImage(frame);
    _send({
      'type': 'response.create',
      'response': {
        'instructions':
            'The camera was just turned on. In one or two short, natural sentences, say what you can see '
            '(the place and anything interesting) and invite the user to ask about it.',
      },
    });
  }

  /// Sends Garad's voice to the earbuds when they are connected (unless the user picked the
  /// loudspeaker), otherwise to the loudspeaker.
  Future<void> _routeAudio() async {
    if (_closed) return;
    final had = headset;
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      headset = devices.any((d) {
        if (d.kind != 'audiooutput') return false;
        final name = '${d.deviceId} ${d.label}'.toLowerCase();
        return name.contains('bluetooth') ||
            name.contains('headset') ||
            name.contains('headphone') ||
            name.contains('airpods') ||
            name.contains('buds');
      });
    } catch (_) {
      headset = false;
    }
    if (headset && !had) _speakerChosen = false; // earbuds just connected: use them
    try {
      if (headset && !_speakerChosen) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
        speakerOn = false;
      } else if (!_routed || headset != had) {
        // Call start, or earbuds just taken out: the loudspeaker. Otherwise keep the user's choice.
        await Helper.setSpeakerphoneOn(true);
        speakerOn = true;
      }
      _routed = true;
    } catch (e) {
      debugPrint('Garad Live audio route: $e');
    }
    if (!_closed) notifyListeners();
  }

  /// The speaker button: loudspeaker ↔ earbuds (or the earpiece when no earbuds are connected).
  Future<void> toggleSpeaker() async {
    if (kIsWeb || _closed) return;
    final next = !speakerOn;
    try {
      if (next) {
        await Helper.setSpeakerphoneOn(true);
      } else if (headset) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
      } else {
        await Helper.setSpeakerphoneOn(false);
      }
      speakerOn = next;
      _speakerChosen = next && headset;
    } catch (e) {
      debugPrint('Garad Live speaker: $e');
    }
    if (!_closed) notifyListeners();
  }

  void setMuted(bool value) {
    muted = value;
    for (final track in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !value;
    }
    notifyListeners();
  }

  void _onEvent(String text) {
    final Map<String, dynamic> event;
    try {
      event = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (event['type']) {
      case 'input_audio_buffer.speech_started':
        // The user is talking (OpenAI has already stopped Garad's voice). Take a picture now, so it
        // is ready the moment they stop.
        userText = '';
        _frame = takeFrame?.call();
        _set(LiveState.userSpeaking);
      case 'input_audio_buffer.speech_stopped':
        _set(LiveState.thinking);
      case 'input_audio_buffer.committed':
        _answer();
      case 'conversation.item.input_audio_transcription.delta':
        userText += (event['delta'] as String?) ?? '';
        notifyListeners();
      case 'conversation.item.input_audio_transcription.completed':
        userText = ((event['transcript'] as String?) ?? userText).trim();
        notifyListeners();
      case 'response.created':
        garadText = '';
        notifyListeners();
      case 'response.output_audio_transcript.delta':
        garadText += (event['delta'] as String?) ?? '';
        notifyListeners();
      case 'output_audio_buffer.started':
        _set(LiveState.speaking);
      case 'output_audio_buffer.stopped' || 'output_audio_buffer.cleared':
        if (state == LiveState.speaking) _set(LiveState.listening);
      case 'response.done':
        final status = (event['response'] as Map<String, dynamic>?)?['status'];
        if (status == 'failed') {
          debugPrint('Garad Live: answer failed: ${jsonEncode(event['response'])}');
          if (state == LiveState.thinking) _set(LiveState.listening);
        }
      case 'error':
        final error = event['error'] as Map<String, dynamic>?;
        final code = error?['code'] as String? ?? '';
        debugPrint('Garad Live: ${error?['message']}');
        // Stopping an answer that already ended is harmless; anything else is worth showing.
        if (!code.contains('cancel') && !code.contains('active_response')) {
          this.error = error?['message'] as String? ?? 'error';
          notifyListeners();
        }
      case 'session.closed':
        _fail('closed');
    }
  }

  /// The user stopped talking: add the camera picture taken meanwhile, then ask for the answer.
  Future<void> _answer() async {
    final pending = _frame;
    _frame = null;
    if (pending != null) {
      try {
        final frame = await pending.timeout(const Duration(seconds: 2));
        if (frame != null) _sendImage(frame);
      } catch (_) {
        // No picture this time: answer from the voice alone.
      }
    }
    _send({'type': 'response.create'});
  }

  void _stopSpeaking() {
    if (state == LiveState.speaking || state == LiveState.thinking) {
      _send({'type': 'response.cancel'});
      _send({'type': 'output_audio_buffer.clear'});
    }
  }

  void _sendImage(Uint8List jpeg) {
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_image', 'image_url': 'data:image/jpeg;base64,${base64Encode(jpeg)}'},
        ],
      },
    });
  }

  void _send(Map<String, Object?> event) {
    final events = _events;
    if (events == null || events.state != RTCDataChannelState.RTCDataChannelOpen) return;
    events.send(RTCDataChannelMessage(jsonEncode(event)));
  }

  void _set(LiveState next) {
    if (_closed || state == next) return;
    state = next;
    notifyListeners();
  }

  void _fail(String reason) {
    if (_closed) return;
    error ??= reason;
    state = LiveState.ended;
    notifyListeners();
  }


  /// Clears a failed attempt (connection and microphone) so [start] can try again.
  Future<void> reset() async {
    final pc = _pc, mic = _mic, events = _events;
    _pc = null;
    _mic = null;
    _events = null;
    try {
      await events?.close();
    } catch (_) {}
    for (final track in mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await mic?.dispose();
    } catch (_) {}
    try {
      await pc?.close();
    } catch (_) {}
    error = null;
    userText = '';
    garadText = '';
    if (!_closed) {
      state = LiveState.connecting;
      notifyListeners();
    }
  }
  /// Ends the call and frees the microphone.
  Future<void> hangUp() async {
    if (_closed) return;
    _closed = true;
    state = LiveState.ended;
    if (!kIsWeb) navigator.mediaDevices.ondevicechange = null;
    try {
      await _events?.close();
    } catch (_) {}
    for (final track in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await _mic?.dispose();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      voice.srcObject = null;
      await voice.dispose();
    } catch (_) {}
  }
}

class LiveException implements Exception {
  const LiveException(this.reason, [this.detail]);

  final String reason;

  /// What exactly went wrong (shown small under the error, to find the cause).
  final String? detail;

  @override
  String toString() => detail == null ? reason : '$reason: $detail';
}

/// A camera picture made small enough for the live connection (about 1024 px, under ~150 KB),
/// still sharp enough to read a page.
Future<Uint8List> shrinkFrame(Uint8List bytes) => compute(_shrink, bytes);

Uint8List _shrink(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final upright = img.bakeOrientation(decoded);
  final longest = upright.width >= upright.height ? upright.width : upright.height;
  final small = longest <= 1024
      ? upright
      : upright.width >= upright.height
      ? img.copyResize(upright, width: 1024, interpolation: img.Interpolation.average)
      : img.copyResize(upright, height: 1024, interpolation: img.Interpolation.average);
  return Uint8List.fromList(img.encodeJpg(small, quality: 75));
}
