import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../auth_state.dart';
import '../call_audio.dart';
import '../chat_strings.dart';
import '../local_pages.dart';
import 'billing_screen.dart';

/// Garad Live: a real-time video call with Garad, like Gemini Live. You talk and show the camera; Garad
/// answers by voice as it sees and hears, and you can speak over it. The call itself is a page bundled
/// with the app (live_client/, served by [LocalPages]) that talks straight to Google's Live API; the
/// browser engine's echo cancellation keeps Garad from hearing its own voice on the speaker. This screen
/// gives the page a one-use key for each ~2-minute block from garad.ai (which pays for it first), and
/// ends the call when the page asks.
class LiveVideoScreen extends StatefulWidget {
  const LiveVideoScreen({super.key});

  @override
  State<LiveVideoScreen> createState() => _LiveVideoScreenState();
}

class _LiveVideoScreenState extends State<LiveVideoScreen> {
  Uri? _page;
  String? _error;
  InAppWebViewController? _web;

  static String _t(String so, String en) => chatStrings.isSomali ? so : en;

  @override
  void initState() {
    super.initState();
    // A video call keeps the screen dark around the camera; the status bar is light on black.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    // Sound on and Garad's voice on the loudspeaker (set again once the page's microphone is on).
    CallAudio.liveStart();
    _start();
  }

  @override
  void dispose() {
    // Leaving by the system back gesture: the page stops the camera, microphone and connection.
    _web?.evaluateJavascript(source: 'window.garadLive && window.garadLive.end()');
    CallAudio.liveEnd();
    super.dispose();
  }

  Future<void> _start() async {
    // The camera and microphone first, with the phone's own permission questions.
    if (!kIsWeb) {
      final statuses = await [Permission.camera, Permission.microphone].request();
      if (statuses.values.any((s) => !s.isGranted)) {
        if (mounted) {
          setState(
            () => _error = _t(
              'Garad Live wuxuu u baahan yahay kamaradda iyo makarafoonka. Ku oggolow Settings.',
              'Garad Live needs the camera and microphone. Allow them in Settings.',
            ),
          );
        }
        return;
      }
    }
    try {
      final page = await LocalPages.live();
      if (mounted) setState(() => _page = page);
    } catch (_) {
      if (mounted) setState(() => _error = _t('Wicitaanka lama furi karo.', 'The call could not be opened.'));
    }
  }

  void _end() {
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return PopScope(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _error != null
            ? _Problem(message: _error!, onClose: _end, onSettings: openAppSettings)
            : page == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri.uri(page.replace(queryParameters: {'lang': chatStrings.isSomali ? 'so' : 'en'})),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  transparentBackground: false,
                  supportZoom: false,
                  disableContextMenu: true,
                  allowFileAccess: false,
                  useShouldOverrideUrlLoading: true,
                  overScrollMode: OverScrollMode.NEVER,
                ),
                onWebViewCreated: (controller) {
                  _web = controller;
                  // A one-use key for the next block of the call (garad.ai pays for it first).
                  controller.addJavaScriptHandler(
                    handlerName: 'liveToken',
                    callback: (_) => context.read<AuthState>().api.liveToken(somali: chatStrings.isSomali),
                  );
                  controller.addJavaScriptHandler(handlerName: 'end', callback: (_) => _end());
                  // The microphone just put the phone in call mode: keep Garad on the loudspeaker.
                  controller.addJavaScriptHandler(handlerName: 'audioReady', callback: (_) => CallAudio.liveStart());
                  controller.addJavaScriptHandler(
                    handlerName: 'upgrade',
                    callback: (_) {
                      if (!mounted) return;
                      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const BillingScreen()));
                    },
                  );
                },
                // The camera and microphone only for the app's own call page.
                onPermissionRequest: (controller, request) async => PermissionResponse(
                  resources: request.resources,
                  action: request.origin.host == '127.0.0.1' && request.origin.port == page.port
                      ? PermissionResponseAction.GRANT
                      : PermissionResponseAction.DENY,
                ),
                shouldOverrideUrlLoading: (controller, action) async {
                  final url = action.request.url;
                  return url != null && url.host == '127.0.0.1' && url.port == page.port
                      ? NavigationActionPolicy.ALLOW
                      : NavigationActionPolicy.CANCEL;
                },
              ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onClose, required this.onSettings});

  final String message;
  final VoidCallback onClose;
  final Future<bool> Function() onSettings;

  @override
  Widget build(BuildContext context) {
    String t(String so, String en) => chatStrings.isSomali ? so : en;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.4)),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, shape: const StadiumBorder()),
                    child: Text(t('Xir', 'Close')),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: onSettings,
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                    child: Text(t('Settings', 'Settings')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
