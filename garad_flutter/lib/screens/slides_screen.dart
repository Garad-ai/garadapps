import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/garad_api.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../local_pages.dart';
import '../theme.dart';

/// A file name as a title: "Online_Business_Presentation.pptx" → "Online Business Presentation".
String slidesTitle(String? name) => (name ?? '')
    .trim()
    .replaceFirst(RegExp(r'\.pptx?$', caseSensitive: false), '')
    .replaceAll(RegExp(r'[_]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A presentation made by Garad, as slides — the same slide view as garad.ai: one slide at a time
/// (swipe or ‹ › to move), a Grid of all slides, and Present (full screen, landscape, tap for the next
/// slide). The slides are drawn by the website's renderer (slides_viewer/, served by [LocalPages]);
/// the controls around them are the app's own. Share sends the real PowerPoint file.
class SlidesScreen extends StatefulWidget {
  const SlidesScreen({super.key, required this.id, this.title});

  final int id;
  final String? title;

  @override
  State<SlidesScreen> createState() => _SlidesScreenState();
}

class _SlidesScreenState extends State<SlidesScreen> {
  Uri? _page;
  Uint8List? _deck;
  Future<Uint8List>? _downloading;
  InAppWebViewController? _web;

  int _count = 0;
  int _slide = 0;
  bool _grid = false;
  bool _presenting = false;
  bool _sharing = false;
  String? _error;

  GaradApi get _api => context.read<AuthState>().api;

  static String _t(String so, String en) => chatStrings.isSomali ? so : en;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    if (_presenting) _restoreScreen();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final page = await LocalPages.slides();
      if (mounted) setState(() => _page = page);
    } catch (_) {
      if (mounted) setState(() => _error = _t('Bandhigga lama furi karo.', 'The slides could not be opened.'));
    }
  }

  /// The deck's bytes (downloaded once; also what Share sends).
  Future<Uint8List> _bytes() async {
    if (_deck != null) return _deck!;
    final download = _downloading ??= _api.downloadDocument(widget.id);
    try {
      return _deck = await download;
    } catch (_) {
      _downloading = null;
      rethrow;
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final bytes = await _bytes();
      var name = (widget.title ?? '').trim();
      if (name.isEmpty) name = 'garad-presentation';
      if (!name.toLowerCase().endsWith('.pptx')) name = '$name.pptx';
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: name)]));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _call(String script) => _web?.evaluateJavascript(source: 'window.garadSlides && window.garadSlides.$script');

  void _go(int delta) => _call(delta > 0 ? 'next()' : 'previous()');

  void _setGrid(bool on) {
    setState(() => _grid = on);
    _call("setView('${on ? 'grid' : 'one'}')");
  }

  Future<void> _present(bool on) async {
    setState(() {
      _presenting = on;
      if (on) _grid = false;
    });
    _call('setView(\'one\')');
    _call('setPresenting($on)');
    if (on) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await _restoreScreen();
    }
  }

  Future<void> _restoreScreen() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ready = _count > 0;

    final body = _error != null
        ? _Failed(message: _error!, onRetry: _retry, onOpenFile: _sharing ? null : _share)
        : _page == null
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri.uri(_page!.replace(queryParameters: {'theme': dark ? 'dark' : 'light'})),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: true,
              supportZoom: false,
              disableContextMenu: true,
              allowFileAccess: false,
              allowFileAccessFromFileURLs: false,
              allowUniversalAccessFromFileURLs: false,
              useShouldOverrideUrlLoading: true,
              overScrollMode: OverScrollMode.NEVER,
              verticalScrollBarEnabled: false,
              horizontalScrollBarEnabled: false,
            ),
            onWebViewCreated: (controller) {
              _web = controller;
              // The page asks for the deck once it is ready.
              controller.addJavaScriptHandler(
                handlerName: 'deck',
                callback: (_) async {
                  try {
                    return base64Encode(await _bytes());
                  } on ApiException catch (e) {
                    if (mounted) setState(() => _error = e.message);
                    return '';
                  }
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'slides',
                callback: (args) {
                  final data = args.isEmpty ? null : args.first;
                  if (data is! Map || !mounted) return;
                  setState(() {
                    if (data['error'] is String) {
                      _error = _t('Bandhigga lama muujin karo.', 'This presentation could not be shown.');
                    } else {
                      _count = (data['count'] as num?)?.toInt() ?? _count;
                      _slide = (data['slide'] as num?)?.toInt() ?? _slide;
                      // Tapping a slide in the Grid opens it: back to one slide.
                      if (data['view'] is String) _grid = data['view'] == 'grid';
                    }
                  });
                },
              );
            },
            // Only the viewer itself: any link inside a slide opens in the browser instead.
            shouldOverrideUrlLoading: (controller, action) async {
              final url = action.request.url;
              return url != null && url.host == '127.0.0.1' && url.port == _page!.port
                  ? NavigationActionPolicy.ALLOW
                  : NavigationActionPolicy.CANCEL;
            },
          );

    return PopScope(
      // Back ends Present first, then closes.
      canPop: !_presenting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _presenting) _present(false);
      },
      child: Scaffold(
        backgroundColor: _presenting ? Colors.black : c.background,
        appBar: _presenting
            ? null
            : AppBar(
                backgroundColor: c.background,
                surfaceTintColor: Colors.transparent,
                leadingWidth: 64,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _RoundButton(
                    icon: Icons.close,
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                title: Text(
                  _displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                actions: [
                  _RoundButton(
                    icon: _grid ? Icons.crop_landscape_outlined : Icons.grid_view_outlined,
                    tooltip: _grid ? _t('Hal bog', 'One slide') : _t('Dhammaan', 'All slides'),
                    onPressed: ready ? () => _setGrid(!_grid) : null,
                  ),
                  const SizedBox(width: 8),
                  _RoundButton(
                    icon: Icons.ios_share,
                    tooltip: chatStrings.share,
                    busy: _sharing,
                    onPressed: _sharing ? null : _share,
                  ),
                  const SizedBox(width: 12),
                ],
              ),
        body: SafeArea(
          top: !_presenting,
          bottom: !_presenting,
          left: !_presenting,
          right: !_presenting,
          child: Column(
            children: [
              Expanded(child: body),
              if (!_presenting && !_grid && ready && _error == null)
                _Controls(
                  slide: _slide,
                  count: _count,
                  onPrevious: _slide > 0 ? () => _go(-1) : null,
                  onNext: _slide < _count - 1 ? () => _go(1) : null,
                  onPresent: () => _present(true),
                  presentLabel: _t('Soo bandhig', 'Present'),
                ),
            ],
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _presenting
            ? _PresentBar(
                slide: _slide,
                count: _count,
                onPrevious: () => _go(-1),
                onNext: () => _go(1),
                onEnd: () => _present(false),
              )
            : null,
      ),
    );
  }

  String get _displayTitle {
    final title = slidesTitle(widget.title);
    return title.isEmpty ? _t('Bandhig', 'Presentation') : title;
  }

  void _retry() {
    setState(() {
      _error = null;
      _count = 0;
      _page = null;
    });
    _start();
  }
}

/// ‹  3 / 8  ›   and   ▶ Present
class _Controls extends StatelessWidget {
  const _Controls({
    required this.slide,
    required this.count,
    required this.onPrevious,
    required this.onNext,
    required this.onPresent,
    required this.presentLabel,
  });

  final int slide;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPresent;
  final String presentLabel;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          _RoundButton(icon: Icons.chevron_left, tooltip: 'Previous slide', onPressed: onPrevious),
          Expanded(
            child: Text(
              '${slide + 1} / $count',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 15, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          _RoundButton(icon: Icons.chevron_right, tooltip: 'Next slide', onPressed: onNext),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onPresent,
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(presentLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Present: a small dark bar — ‹ 5 / 8 › ✕ — like the website's slideshow.
class _PresentBar extends StatelessWidget {
  const _PresentBar({
    required this.slide,
    required this.count,
    required this.onPrevious,
    required this.onNext,
    required this.onEnd,
  });

  final int slide;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tip, VoidCallback onTap) => IconButton(
      icon: Icon(icon, color: Colors.white, size: 22),
      tooltip: tip,
      onPressed: onTap,
    );
    return Opacity(
      opacity: 0.85,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: const Color(0xCC1A1A1A), borderRadius: BorderRadius.circular(24)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(Icons.chevron_left, 'Previous slide', onPrevious),
            Text(
              '${slide + 1} / $count',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
            ),
            button(Icons.chevron_right, 'Next slide', onNext),
            button(Icons.close, 'End the slideshow', onEnd),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry, required this.onOpenFile});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 15)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: Text(chatStrings.retry)),
            // The PowerPoint file still opens in another app.
            TextButton.icon(
              onPressed: onOpenFile,
              icon: const Icon(Icons.ios_share, size: 18),
              label: Text(chatStrings.openFile),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onPressed, this.busy = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return IconButton.filledTonal(
      style: IconButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.text),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: busy
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon),
    );
  }
}
