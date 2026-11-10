import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:garad_agent/garad_agent.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agent_actions.dart';
import '../app_state.dart';
import '../bridge.dart';
import '../config.dart';
import '../remote_config.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/app_menu.dart';
import '../widgets/blocking_screen.dart';
import '../widgets/notice_banner.dart';
import 'agent_screen.dart';

/// Opens a link outside the app: web pages in an in-app browser tab, the rest in their app.
void openExternally(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final web =
      RegExp(r'^https?:', caseSensitive: false).hasMatch(url) &&
      !RegExp(r'^https://wa\.me/', caseSensitive: false).hasMatch(url);
  launchUrl(uri, mode: web ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication).catchError((_) => false);
}

/// The Garad AI app: the garad.ai web app (Chat Pro) in a native shell, so the app has exactly
/// the same design, account, data and AI features as the website. The admin controls updates,
/// maintenance, an announcement and the menu links (Settings › Mobile App).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.openVoice});

  /// Opened from the "Talk to Garad" shortcut: start straight in Garad Voice.
  final bool openVoice;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  InAppWebViewController? _webView;
  PullToRefreshController? _pullToRefresh;
  late final AppLifecycleListener _lifecycle;
  late final AppState _app;
  late int _handledVoiceRequest;
  final Speaker _speaker = Speaker();
  final ValueNotifier<String?> _updateNote = ValueNotifier(null);
  bool _menuOpen = false;
  bool _canGoBack = false;
  double _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _handledVoiceRequest = _app.voiceRequest;
    _app.addListener(_onAppState);
    _app.loadConfig();
    // Read the admin's settings again whenever the app comes back to the front.
    _lifecycle = AppLifecycleListener(onResume: _app.loadConfig);
    if (!kIsWeb) {
      _pullToRefresh = PullToRefreshController(
        settings: PullToRefreshSettings(color: Palette.light.brand),
        onRefresh: () => _webView?.reload(),
      );
    }
    // Hide the splash screen after the first page load, or after a few seconds at most.
    Future.delayed(const Duration(seconds: 8), FlutterNativeSplash.remove);
  }

  @override
  void dispose() {
    _app.removeListener(_onAppState);
    _lifecycle.dispose();
    _speaker.stop();
    _updateNote.dispose();
    super.dispose();
  }

  /// The "Talk to Garad" shortcut while the app is already open.
  void _onAppState() {
    if (_app.voiceRequest == _handledVoiceRequest) return;
    _handledVoiceRequest = _app.voiceRequest;
    _openInPage(withVoice(startUrl));
  }

  void _openInPage(String url) {
    _webView?.evaluateJavascript(source: 'window.location.href = ${jsonEncode(url)};');
  }

  /// Runs a script in the page, natively when possible: that also works while another app is
  /// in front, which is where the agent works.
  Future<void> _runInPage(String script) async {
    if (!await GaradAgent.evaluateInPage(script)) await _webView?.evaluateJavascript(source: script);
  }

  void _onMessage(List<dynamic> arguments) {
    if (arguments.isEmpty || arguments.first is! String) return;
    Map<String, Object?> message;
    try {
      final decoded = jsonDecode(arguments.first as String);
      if (decoded is! Map<String, Object?>) return;
      message = decoded;
    } catch (_) {
      return; // Not a message from the Chat Pro app shell or the download bridge.
    }

    switch (message['type']) {
      case 'theme':
        final color = message['background'] is String ? parseCssColor(message['background']! as String) : null;
        if (color != null) _app.setPageTheme(color, message['dark'] == true);

      case 'agentAction':
        final id = message['id'];
        final name = message['name'];
        if (id is! String || name is! String) return;
        // A phone action requested by Garad Voice; the result goes back to the page.
        final args = message['args'] is Map ? Map<String, Object?>.from(message['args']! as Map) : <String, Object?>{};
        final run = GaradAgent.isSupported && screenActions.contains(name)
            ? GaradAgent.perform(name, args)
            : runAgentAction(name, args);
        run
            .catchError((_) => <String, Object?>{'ok': false, 'message': 'The action failed on the phone.'})
            .then(
              (result) => _runInPage(
                'window.__garadAgentResult && window.__garadAgentResult(${jsonEncode(id)}, ${jsonEncode(result)});',
              ),
            );

      case 'openAppMenu':
        _openMenu();

      case 'copy':
        if (message['text'] is String) copyText(message['text']! as String);

      case 'download':
        if (message['base64'] is! String) return;
        saveDownload(
          message['name'] is String ? message['name']! as String : 'download',
          message['mime'] is String ? message['mime']! as String : 'application/octet-stream',
          message['base64']! as String,
        ).catchError((_) => _showError(strings.downloadFailed));

      case 'speak':
        if (message['text'] is! String) return;
        _speaker.speak(
          message['text']! as String,
          language: message['lang'] is String ? message['lang']! as String : null,
          rate: message['rate'] is num ? (message['rate']! as num).toDouble() : null,
          notify: (event) => _webView?.evaluateJavascript(
            source: 'window.__garadSpeech && window.__garadSpeech(${jsonEncode(event)});',
          ),
        );

      case 'speakStop':
        _speaker.stop();

      case 'downloadError':
        final url = message['url'];
        if (url is String && RegExp(r'^https:', caseSensitive: false).hasMatch(url)) {
          launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
        } else {
          _showError(strings.downloadFailed);
        }
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openMenu() async {
    if (_menuOpen || !mounted) return;
    _updateNote.value = null;
    _menuOpen = true;
    final background = _app.pageBackground ?? Palette.of(context).background;
    await showAppMenu(
      context,
      config: _app.config,
      version: _app.appVersion,
      background: background,
      updateNote: _updateNote,
      onTalk: () => _openInPage(withVoice(startUrl)),
      onAgent: GaradAgent.isSupported
          ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AgentScreen()))
          : null,
      onOpenLink: (url) => isSiteUrl(url) ? _openInPage(url) : openExternally(url),
      onCheckUpdates: () async {
        final next = await _app.loadConfig();
        if (updateStatus(next, _app.appVersion) == UpdateStatus.none) {
          _updateNote.value = strings.upToDate;
        } else if (mounted) {
          Navigator.of(context).pop();
          _app.dismissUpdate(false);
        }
      },
    );
    _menuOpen = false;
  }

  void _openUpdate() {
    final url = _app.config?.updateUrl;
    if (url == null) return;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) {
      openExternally(url);
      return false;
    });
  }

  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url?.toString() ?? '';
    if (url.startsWith('about:') || url.startsWith('blob:') || url.startsWith('data:')) {
      return NavigationActionPolicy.ALLOW;
    }
    // Embedded frames (videos, maps, payment widgets) load inside the page.
    if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;
    if (isSiteUrl(url)) return NavigationActionPolicy.ALLOW;
    openExternally(url);
    return NavigationActionPolicy.CANCEL;
  }

  /// Camera and microphone for the site itself (photos, voice chat, dictation); others are denied.
  Future<PermissionResponse> _onPermissionRequest(InAppWebViewController controller, PermissionRequest request) async {
    final allowed = isSiteUrl(request.origin.toString());
    if (allowed && !kIsWeb) {
      final wanted = <Permission>[
        if (request.resources.contains(PermissionResourceType.CAMERA)) Permission.camera,
        if (request.resources.contains(PermissionResourceType.MICROPHONE)) Permission.microphone,
      ];
      final statuses = await wanted.request();
      if (statuses.values.any((status) => !status.isGranted)) {
        return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
      }
    }
    return PermissionResponse(
      resources: request.resources,
      action: allowed ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY,
    );
  }

  Future<void> _updateCanGoBack() async {
    final canGoBack = await _webView?.canGoBack() ?? false;
    if (mounted && canGoBack != _canGoBack) setState(() => _canGoBack = canGoBack);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = Palette.of(context);
    final background = app.pageBackground ?? c.background;
    final dark = app.pageDark ?? MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final config = app.config;
    final status = app.status;

    Widget body;
    if (config?.maintenance ?? false) {
      body = BlockingScreen(
        title: strings.maintenanceTitle,
        body: config?.maintenanceMessage ?? strings.maintenanceBody,
        actionLabel: strings.retry,
        onAction: app.loadConfig,
        background: background,
      );
    } else if (status == UpdateStatus.required) {
      body = BlockingScreen(
        title: strings.updateRequiredTitle,
        body: config?.updateMessage ?? strings.updateRequiredBody,
        actionLabel: config?.updateUrl != null ? strings.update : null,
        onAction: _openUpdate,
        background: background,
      );
    } else {
      final announcement = config?.announcement;
      body = Column(
        children: [
          if (status == UpdateStatus.available && !app.updateDismissed)
            NoticeBanner(
              message: config?.updateMessage ?? strings.updateAvailable,
              actionLabel: config?.updateUrl != null ? strings.update : null,
              onAction: _openUpdate,
              onDismiss: app.dismissUpdate,
              dismissLabel: strings.later,
            ),
          if (announcement != null && app.dismissedAnnouncement != announcement.message)
            NoticeBanner(
              message: announcement.message,
              actionLabel: announcement.url != null ? '›' : null,
              onAction: () {
                final url = announcement.url;
                if (url != null) isSiteUrl(url) ? _openInPage(url) : openExternally(url);
              },
              onDismiss: () => app.dismissAnnouncement(announcement.message),
              dismissLabel: strings.close,
            ),
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(value: _progress, minHeight: 2, color: c.brand, backgroundColor: background),
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(widget.openVoice ? withVoice(startUrl) : startUrl)),
                  initialSettings: InAppWebViewSettings(
                    applicationNameForUserAgent: 'GaradApp/${app.appVersion}',
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    thirdPartyCookiesEnabled: true,
                    sharedCookiesEnabled: true,
                    allowsBackForwardNavigationGestures: true,
                    allowsInlineMediaPlayback: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowFileAccess: false,
                    supportMultipleWindows: false,
                    useShouldOverrideUrlLoading: true,
                    useOnDownloadStart: true,
                    textZoom: 100,
                    overScrollMode: OverScrollMode.NEVER,
                    transparentBackground: true,
                    isInspectable: kDebugMode,
                  ),
                  initialUserScripts: UnmodifiableListView([
                    UserScript(
                      source: documentStartScript(agent: GaradAgent.isSupported),
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ]),
                  pullToRefreshController: _pullToRefresh,
                  onWebViewCreated: (controller) {
                    _webView = controller;
                    controller.addJavaScriptHandler(handlerName: bridgeHandlerName, callback: _onMessage);
                  },
                  shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
                  onPermissionRequest: _onPermissionRequest,
                  onProgressChanged: (_, progress) => setState(() => _progress = progress / 100),
                  onLoadStop: (_, _) {
                    setState(() => _progress = 1);
                    _pullToRefresh?.endRefreshing();
                    FlutterNativeSplash.remove();
                    _updateCanGoBack();
                  },
                  onUpdateVisitedHistory: (_, _, _) => _updateCanGoBack(),
                  onReceivedError: (_, request, error) {
                    _pullToRefresh?.endRefreshing();
                    if (request.isForMainFrame ?? true) setState(() => _failed = true);
                  },
                  // File responses: fetch them in the page (with the user's cookies) so they go
                  // through the same save/share bridge as Chat Pro's own downloads.
                  onDownloadStartRequest: (controller, request) async {
                    await controller.evaluateJavascript(
                      source:
                          'window.__garadDownload && window.__garadDownload(${jsonEncode(request.url.toString())});',
                    );
                  },
                  onRenderProcessGone: (controller, _) => controller.reload(),
                  onWebContentProcessDidTerminate: (controller) => controller.reload(),
                ),
                if (_failed)
                  Positioned.fill(
                    child: BlockingScreen(
                      title: strings.offlineTitle,
                      body: strings.offlineBody,
                      actionLabel: strings.retry,
                      onAction: () {
                        setState(() => _failed = false);
                        _webView?.reload();
                      },
                      background: background,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      // Android back: close the menu (the sheet handles that), go back inside the website, then leave.
      child: PopScope(
        canPop: !_canGoBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _canGoBack) _webView?.goBack();
        },
        child: Scaffold(
          backgroundColor: background,
          body: SafeArea(child: body),
        ),
      ),
    );
  }
}
