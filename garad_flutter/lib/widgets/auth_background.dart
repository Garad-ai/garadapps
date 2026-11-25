import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api/models.dart';

/// The website's sign-in picture filling the screen: the admin's looping video (silent), or the
/// slides taking turns every 5 seconds like on the website. Like the website, with a video only the
/// video is shown (it fades in once it plays); the pictures appear only if the video can't play.
/// Used behind the welcome screen and the Sign in / Sign up screen.
class AuthBackground extends StatefulWidget {
  const AuthBackground({super.key, required this.visual});

  final WelcomeVisual visual;

  @override
  State<AuthBackground> createState() => _AuthBackgroundState();
}

class _AuthBackgroundState extends State<AuthBackground> {
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _videoFailed = false;
  int _slide = 0;
  Timer? _turns;

  @override
  void initState() {
    super.initState();
    final video = widget.visual.video;
    if (video != null) {
      _startVideo(video);
    } else {
      _startSlides();
    }
  }

  void _startSlides() {
    if (widget.visual.pictures.length < 2) return;
    _turns = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _slide = (_slide + 1) % widget.visual.pictures.length);
    });
  }

  Future<void> _startVideo(String url) async {
    // Silent, and without taking the phone's sound from music the user is playing.
    final video = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = video;
    try {
      await video.initialize();
      await video.setVolume(0);
      await video.setLooping(true);
      await video.play();
      if (mounted) setState(() => _videoReady = true);
    } catch (_) {
      // The video can't play here: the pictures instead.
      if (!mounted) return;
      setState(() => _videoFailed = true);
      _startSlides();
    }
  }

  @override
  void dispose() {
    _turns?.cancel();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pictures = widget.visual.pictures;
    final video = _video;
    final showPictures = widget.visual.video == null || _videoFailed;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showPictures && pictures.isNotEmpty)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            child: Image.network(
              pictures[_slide % pictures.length],
              key: ValueKey(_slide),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        if (video != null)
          AnimatedOpacity(
            opacity: _videoReady ? 1 : 0,
            duration: const Duration(milliseconds: 600),
            child: _videoReady
                ? FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: video.value.size.width,
                      height: video.value.size.height,
                      child: VideoPlayer(video),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}
