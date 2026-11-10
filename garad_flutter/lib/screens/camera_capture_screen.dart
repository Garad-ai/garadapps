import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../chat_strings.dart';

/// Takes one photo inside the app and returns it (JPEG bytes), or null when closed.
///
/// Used in the browser: there the photo picker's "camera" only opens a file-upload window on a
/// computer, so ＋ › Camera opens this live camera (the webcam) instead. Phones use their own
/// camera app (image_picker).
Future<Uint8List?> takePhotoInApp(BuildContext context) => Navigator.of(
  context,
).push<Uint8List>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CameraCaptureScreen()));

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  String? _error;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('none', 'No camera');
      // A phone's back camera first; a laptop has only its webcam.
      final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _index = back < 0 ? 0 : back;
      await _open();
    } catch (_) {
      if (mounted) setState(() => _error = chatStrings.cameraUnavailable);
    }
  }

  Future<void> _open() async {
    final controller = CameraController(_cameras[_index], ResolutionPreset.high, enableAudio: false);
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    final old = _camera;
    setState(() {
      _camera = controller;
      _error = null;
    });
    await old?.dispose();
  }

  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    _index = (_index + 1) % _cameras.length;
    try {
      await _open();
    } catch (_) {
      if (mounted) setState(() => _error = chatStrings.cameraUnavailable);
    }
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _taking) return;
    setState(() => _taking = true);
    try {
      final bytes = await (await camera.takePicture()).readAsBytes();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (_) {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (camera != null && camera.value.isInitialized)
              Center(
                child: AspectRatio(
                  // The preview's shape: landscape for a webcam, portrait on a phone held upright.
                  aspectRatio: kIsWeb ? camera.value.aspectRatio : 1 / camera.value.aspectRatio,
                  child: CameraPreview(camera),
                ),
              )
            else
              Center(
                child: _error == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
              ),
            // ✕ close
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(
                tooltip: chatStrings.close,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
            // ◯ shutter · flip
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 56),
                  const SizedBox(width: 24),
                  GestureDetector(
                    onTap: _shoot,
                    child: Semantics(
                      button: true,
                      label: chatStrings.camera,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        padding: const EdgeInsets.all(5),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _taking ? Colors.white54 : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 56,
                    child: _cameras.length > 1
                        ? IconButton(
                            onPressed: _flip,
                            icon: const Icon(Icons.flip_camera_ios_outlined, color: Colors.white, size: 28),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
