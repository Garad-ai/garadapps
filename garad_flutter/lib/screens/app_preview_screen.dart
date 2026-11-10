import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_messages.dart';
import '../chat_strings.dart';
import '../theme.dart';
import '../widgets/answer_view.dart';

/// Opens an app or website the AI built, full screen, like Claude's artifact panel. Returns the change
/// the user asked for ("make the buttons bigger", "fix this error…"), or null when they just closed it.
/// [onOpenChat] adds "Open chat" to the menu (from Artifacts).
Future<String?> openAppPreview(
  BuildContext context,
  AppPart app, {
  int version = 1,
  bool canAskForChanges = true,
  VoidCallback? onOpenChat,
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        AppPreviewScreen(app: app, version: version, canAskForChanges: canAskForChanges, onOpenChat: onOpenChat),
  ),
);

/// The title of an app: an HTML page's <title>, or a React component's name ("BudgetTracker" →
/// "Budget Tracker").
String appTitle(String source, {required bool react}) {
  if (!react) {
    final title = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(source)?.group(1);
    final cleaned = title?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return cleaned.isEmpty ? chatStrings.website : cleaned;
  }
  final name =
      RegExp(r'export\s+default\s+function\s+([A-Z]\w*)').firstMatch(source)?.group(1) ??
      RegExp(r'export\s+default\s+([A-Z]\w*)').firstMatch(source)?.group(1) ??
      RegExp(r'function\s+([A-Z]\w*)\s*\(').firstMatch(source)?.group(1);
  if (name == null || name == 'App') return chatStrings.app;
  return name.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
}

/// Reports the page's errors to the app (phones: the web view's handler; browsers: the parent page)
/// and gives pages that use localStorage a working one where the preview's origin has none.
const _reporter = '''
<script>
(function () {
  var waiting = [];
  function send(m) {
    var bridge = window.flutter_inappwebview;
    if (bridge && bridge.callHandler) { bridge.callHandler("garadAppError", m); return true; }
    return false;
  }
  window.addEventListener("flutterInAppWebViewPlatformReady", function () { waiting.splice(0).forEach(send); });
  function report(error) {
    var m = String(error && error.message ? error.message : error).slice(0, 600);
    if (!m || m === "Script error.") return;
    if (send(m)) return;
    try { if (window.parent !== window) window.parent.postMessage({ garadAppError: m }, "*"); } catch (e) {}
    waiting.push(m);
  }
  window.garadReport = report;
  window.addEventListener("error", function (e) { report(e.error || e.message); });
  window.addEventListener("unhandledrejection", function (e) { report(e.reason); });
  try { window.localStorage.getItem("garad"); } catch (e) {
    var data = {};
    var memory = {
      getItem: function (k) { return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null; },
      setItem: function (k, v) { data[k] = String(v); },
      removeItem: function (k) { delete data[k]; },
      clear: function () { data = {}; },
      key: function (i) { return Object.keys(data)[i] || null; },
      get length() { return Object.keys(data).length; }
    };
    try { Object.defineProperty(window, "localStorage", { value: memory, configurable: true }); } catch (e2) {}
  }
})();
</script>''';

/// An HTML page as the preview runs it: the error reporter first, then the page.
String htmlPreviewPage(String source) {
  final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(source);
  if (head != null) return source.replaceRange(head.end, head.end, _reporter);
  return '$_reporter\n$source';
}

/// A React component as a page that runs it (same libraries and versions as the website's preview):
/// React, Tailwind, lucide-react icons and Recharts from pinned CDN builds; Babel turns the JSX into
/// JavaScript in the page.
String reactPreviewPage(String source) {
  const cdn = 'https://cdn.jsdelivr.net/npm';
  String script(String src) => '<script src="$src"></script>';
  // JSON keeps the source a plain string; "<" is escaped so the code cannot close the <script> tag.
  final embedded = jsonEncode(source)
      .replaceAll("<", "${String.fromCharCode(92)}x3c"); // backslash x3c: JavaScript reads it as "<"
  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
$_reporter
${script('https://cdn.tailwindcss.com/3.4.16')}
<style>body{margin:0;font-family:ui-sans-serif,system-ui,sans-serif}#garad-error{margin:16px;padding:14px 16px;border-radius:10px;color:#991b1b;background:#fef2f2;font:13px/1.5 ui-monospace,monospace;white-space:pre-wrap}</style>
</head>
<body>
<div id="root"></div>
<pre id="garad-error" hidden></pre>
${script('$cdn/react@18.3.1/umd/react.production.min.js')}
${script('$cdn/react-dom@18.3.1/umd/react-dom.production.min.js')}
${script('$cdn/prop-types@15.8.1/prop-types.min.js')}
<script>window.react = window.React;</script>
${script('$cdn/lucide-react@0.468.0/dist/umd/lucide-react.min.js')}
${script('$cdn/recharts@2.15.0/umd/Recharts.min.js')}
${script('$cdn/@babel/standalone@7.26.4/babel.min.js')}
<script>window.GARAD_SOURCE = $embedded;</script>
<script>
(function () {
  var box = document.getElementById("garad-error");
  function show(error) {
    box.hidden = false;
    box.textContent = "This app could not run:\\n\\n" + (error && error.message ? error.message : String(error));
    window.garadReport(error);
  }
  var modules = { react: React, "react-dom": ReactDOM, "react-dom/client": ReactDOM, "lucide-react": window.LucideReact, recharts: window.Recharts };
  function load(name) {
    if (modules[name]) return modules[name];
    throw new Error('"' + name + '" is not available in the preview. You can use react, lucide-react and recharts, and Tailwind classes.');
  }
  var Boundary = (function (Base) {
    function Boundary(props) { Base.call(this, props); this.state = { error: null }; }
    Boundary.prototype = Object.create(Base.prototype);
    Boundary.getDerivedStateFromError = function (error) { return { error: error }; };
    Boundary.prototype.render = function () {
      if (this.state.error) { show(this.state.error); return null; }
      return this.props.children;
    };
    return Boundary;
  })(React.Component);
  try {
    var code = Babel.transform(window.GARAD_SOURCE, {
      filename: "App.tsx",
      presets: [["react", { runtime: "classic" }], ["typescript", { isTSX: true, allExtensions: true }]],
      plugins: ["transform-modules-commonjs"]
    }).code;
    var module = { exports: {} };
    new Function("require", "module", "exports", "React", code)(load, module, module.exports, React);
    var App = module.exports.default || Object.keys(module.exports).map(function (k) { return module.exports[k]; }).find(function (v) { return typeof v === "function"; });
    if (!App) throw new Error('The code has no component to show. Add "export default" to the main component.');
    ReactDOM.createRoot(document.getElementById("root")).render(React.createElement(Boundary, null, React.createElement(App)));
  } catch (error) {
    show(error);
  }
})();
</script>
</body>
</html>''';
}

/// The page that runs [app].
String appPreviewPage(AppPart app) => app.react ? reactPreviewPage(app.source) : htmlPreviewPage(app.source);

/// Claude-style app panel: the running app (Preview) or its code (Code), Copy / Share, and a bar to
/// ask Garad for changes — the vibe-coding loop. When the app hits an error, "Fix it" asks Garad to
/// fix that exact error.
class AppPreviewScreen extends StatefulWidget {
  const AppPreviewScreen({
    super.key,
    required this.app,
    this.version = 1,
    this.canAskForChanges = true,
    this.onOpenChat,
  });

  /// Opens the chat the app was built in (shown in the menu when set).
  final VoidCallback? onOpenChat;

  final AppPart app;
  final int version;
  final bool canAskForChanges;

  /// Builds the running app. Replaced in tests (there is no web view there).
  @visibleForTesting
  static Widget Function(String page, ValueChanged<String> onError, Key key) previewBuilder = _webView;

  @override
  State<AppPreviewScreen> createState() => _AppPreviewScreenState();
}

/// Only the preview itself may load in the web view; links to other sites open in the browser.
const _origin = 'https://app.garad.local/';

Widget _webView(String page, ValueChanged<String> onError, Key key) => InAppWebView(
  key: key,
  initialData: InAppWebViewInitialData(data: page, baseUrl: WebUri(_origin)),
  initialSettings: InAppWebViewSettings(
    javaScriptEnabled: true,
    useShouldOverrideUrlLoading: true,
    allowFileAccess: false,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    mediaPlaybackRequiresUserGesture: false,
    transparentBackground: false,
    supportZoom: false,
    iframeAllow: 'clipboard-write; fullscreen',
    iframeSandbox: {Sandbox.ALLOW_SCRIPTS, Sandbox.ALLOW_FORMS, Sandbox.ALLOW_MODALS, Sandbox.ALLOW_POPUPS},
  ),
  onWebViewCreated: (controller) {
    if (kIsWeb) return;
    controller.addJavaScriptHandler(
      handlerName: 'garadAppError',
      callback: (args) => onError(args.isEmpty ? '' : '${args.first}'),
    );
  },
  shouldOverrideUrlLoading: (controller, action) async {
    final uri = action.request.url;
    final inPage =
        uri == null ||
        uri.scheme == 'about' ||
        uri.scheme == 'data' ||
        uri.scheme == 'blob' ||
        uri.toString().startsWith(_origin);
    if (inPage || !action.isForMainFrame) return NavigationActionPolicy.ALLOW;
    if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto' || uri.scheme == 'tel') {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return NavigationActionPolicy.CANCEL;
  },
);

class _AppPreviewScreenState extends State<AppPreviewScreen> {
  late final String _page = appPreviewPage(widget.app);
  late final String _title = appTitle(widget.app.source, react: widget.app.react);
  final _request = TextEditingController();
  bool _showCode = false;
  int _run = 0; // a new number reloads the preview
  String? _error;
  void Function()? _stopListening;

  @override
  void initState() {
    super.initState();
    _stopListening = listenForAppErrors(_onError);
    _request.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _stopListening?.call();
    _request.dispose();
    super.dispose();
  }

  void _onError(String message) {
    if (!mounted || message.trim().isEmpty || _error != null) return;
    setState(() => _error = message.trim());
  }

  void _reload() => setState(() {
    _error = null;
    _run++;
  });

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.app.source));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(chatStrings.codeCopied)));
  }

  Future<void> _share() async {
    final name =
        '${_title.replaceAll(RegExp(r'[^\w\- ]'), '').trim().replaceAll(' ', '-').toLowerCase()}'
        '${widget.app.react ? '.jsx' : '.html'}';
    // A React app is shared as a page that runs it, so it opens in any browser.
    final bytes = utf8.encode(widget.app.react ? reactPreviewPage(widget.app.source) : widget.app.source);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: name.replaceAll('.jsx', '.html'), mimeType: 'text/html')],
          subject: _title,
        ),
      );
    } catch (_) {
      await _copy();
    }
  }

  void _ask([String? text]) {
    final request = (text ?? _request.text).trim();
    if (request.isEmpty) return;
    Navigator.of(context).pop(request);
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = chatStrings;
    final kind = widget.app.react ? s.appKind : s.websiteKind;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: s.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.version > 1 ? '$kind · ${s.appVersion(widget.version)}' : kind,
              style: TextStyle(color: c.muted, fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          if (!_showCode) IconButton(icon: const Icon(Icons.refresh), tooltip: s.reload, onPressed: _reload),
          PopupMenuButton<VoidCallback>(
            icon: const Icon(Icons.more_horiz),
            tooltip: s.more,
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              if (widget.onOpenChat != null)
                PopupMenuItem(
                  value: () {
                    Navigator.of(context).pop();
                    widget.onOpenChat!();
                  },
                  child: _MenuRow(icon: Icons.chat_bubble_outline, label: s.openChat),
                ),
              PopupMenuItem(
                value: _copy,
                child: _MenuRow(icon: Icons.copy_outlined, label: s.copyCode),
              ),
              PopupMenuItem(
                value: _share,
                child: _MenuRow(icon: Icons.ios_share, label: s.shareFile),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: _Tabs(showCode: _showCode, onChanged: (code) => setState(() => _showCode = code)),
            ),
            Divider(height: 1, color: c.line),
            Expanded(
              child: IndexedStack(
                index: _showCode ? 1 : 0,
                children: [
                  ColoredBox(
                    color: Colors.white,
                    child: AppPreviewScreen.previewBuilder(_page, _onError, ValueKey('app-preview-$_run')),
                  ),
                  _CodeView(code: widget.app.source),
                ],
              ),
            ),
            if (_error != null)
              _ErrorBar(
                message: _error!,
                onFix: widget.canAskForChanges ? () => _ask(s.fixAppError(_error!)) : null,
                onDismiss: () => setState(() => _error = null),
              ),
            if (widget.canAskForChanges)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: c.line),
                  ),
                  padding: const EdgeInsets.only(left: 16, right: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _request,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _ask(),
                          decoration: InputDecoration(
                            hintText: s.askForChanges,
                            border: InputBorder.none,
                            hintStyle: TextStyle(color: c.faint),
                          ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: s.send,
                        style: IconButton.styleFrom(
                          backgroundColor: c.brand,
                          disabledBackgroundColor: c.line,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _request.text.trim().isEmpty ? null : _ask,
                        icon: const Icon(Icons.arrow_upward, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 19), const SizedBox(width: 12), Text(label)]);
}

/// Preview | Code, a small segmented pill like Claude's.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.showCode, required this.onChanged});

  final bool showCode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    Widget tab(String label, IconData icon, bool code) {
      final selected = showCode == code;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(code),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? (Theme.of(context).brightness == Brightness.dark ? c.surfaceStrong : Colors.white)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: selected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? c.text : c.muted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(color: selected ? c.text : c.muted, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [tab(chatStrings.preview, Icons.play_circle_outline, false), tab(chatStrings.code, Icons.code, true)],
      ),
    );
  }
}

/// The code with line numbers; scrolls both ways and can be selected.
class _CodeView extends StatelessWidget {
  const _CodeView({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final lines = code.split('\n');
    const style = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.55);
    return ColoredBox(
      color: c.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                [for (var i = 1; i <= lines.length; i++) '$i'].join('\n'),
                textAlign: TextAlign.right,
                style: style.copyWith(color: c.faint),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 16),
                child: SelectableText(code, style: style.copyWith(color: c.text)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "This app hit an error" with Fix it (asks Garad to fix that error).
class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onFix, required this.onDismiss});

  final String message;
  final VoidCallback? onFix;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 19, color: c.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chatStrings.appError,
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (onFix != null)
            FilledButton(
              onPressed: onFix,
              style: FilledButton.styleFrom(backgroundColor: c.danger, visualDensity: VisualDensity.compact),
              child: Text(chatStrings.fixIt),
            ),
          IconButton(icon: const Icon(Icons.close, size: 18), tooltip: chatStrings.close, onPressed: onDismiss),
        ],
      ),
    );
  }
}
