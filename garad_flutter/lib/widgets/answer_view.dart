import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/garad_api.dart';
import '../auth_state.dart';
import '../api/models.dart';
import '../chat_strings.dart';
import '../screens/app_preview_screen.dart';
import '../screens/document_screen.dart';
import '../screens/image_edit_screen.dart';
import '../screens/library_screen.dart';
import '../theme.dart';
import 'code_block.dart';

/// One piece of an answer: text, a file the AI created, a generated image, or a question with options.
sealed class AnswerPart {
  const AnswerPart();
}

class TextPart extends AnswerPart {
  const TextPart(this.markdown);
  final String markdown;
}

class FilePart extends AnswerPart {
  const FilePart({required this.name, required this.kind, required this.url, this.size});
  final String name;

  /// pdf · document · spreadsheet · presentation · …
  final String kind;
  final String url;
  final int? size;
}

class ImagePart extends AnswerPart {
  const ImagePart(this.url);
  final String url;
}

/// An app or website the AI wrote: a whole HTML page (```html) or a React component (```jsx / tsx).
/// [done] is false while the code is still being written.
class AppPart extends AnswerPart {
  const AppPart({required this.source, required this.react, this.done = true});
  final String source;
  final bool react;
  final bool done;

  String get title => appTitle(source, react: react);
  int get lines => '\n'.allMatches(source).length + 1;
}

/// A code block (```python …): a card with Copy, and Run for Python and JavaScript.
class CodePart extends AnswerPart {
  const CodePart({required this.language, required this.code, this.done = true, this.setup = const []});
  final String language;
  final String code;
  final bool done;

  /// The same example's earlier parts (run silently first; see [CodeBlock.setup]).
  final List<String> setup;
}

/// Pictures from the web for the idea above it (ChatGPT-style), found by [query].
class PhotosPart extends AnswerPart {
  const PhotosPart(this.query);
  final String query;
}

class ChoicesPart extends AnswerPart {
  const ChoicesPart(this.question, this.options);
  final String question;
  final List<({String label, String description})> options;
}

/// The website's answer format → parts:
///  * `<div class="garad-tool-result-card …" data-kind data-size><span>name</span><a href=…>` → [FilePart]
///  * `[[GARAD_IMAGE_RESULT:<base64url of the image link>]]` → [ImagePart]
///  * `[[GARAD_PHOTOS: query]]` (under an idea's heading) → [PhotosPart]
///  * ```garad-choices {"question","options":[{"label","description"}]}``` → [ChoicesPart]
///  * other `[[GARAD_…]]` markers are hidden, and so is one still being written at the end.
List<AnswerPart> parseAnswer(String content) {
  final parts = <AnswerPart>[];
  final pattern = RegExp(
    r'<div class="garad-tool-result-card([^>]*)>([\s\S]*?)</div>'
    r'|\[\[GARAD_IMAGE_RESULT:([A-Za-z0-9_-]+)\]\]'
    r'|\[\[GARAD_PHOTOS:\s*([^\]\n]+?)\s*\]\]'
    r'|\[\[GARAD_[A-Z_]+:[^\]]*\]\]'
    r'|```garad-choices\s*\n?([\s\S]*?)\n?```'
    r'|```(html|jsx|tsx)[ \t]*\n([\s\S]*?)(\n```|$)'
    r'|```([\w+#.-]*)[ \t]*\n([\s\S]*?)(\n[ \t]*```|$)'
    r'|\[\[?(?:G(?:A(?:R(?:A(?:D[A-Z_]*(?::[^\]\n]*)?)?)?)?)?)?\]?$',
  );
  var at = 0;
  void text(String s) {
    if (s.trim().isNotEmpty) parts.add(TextPart(s.trim()));
  }

  for (final m in pattern.allMatches(content)) {
    text(content.substring(at, m.start));
    at = m.end;
    if (m.group(2) != null) {
      final attrs = m.group(1)!;
      final body = m.group(2)!;
      final url = RegExp(r'href="([^"]+)"').firstMatch(body)?.group(1);
      if (url == null) continue;
      String attr(String name) => RegExp('data-$name="([^"]*)"').firstMatch(attrs)?.group(1) ?? '';
      final name = RegExp(r'<span>([\s\S]*?)</span>').firstMatch(body)?.group(1) ?? 'file';
      parts.add(
        FilePart(name: _unescape(name), kind: attr('kind'), url: _unescape(url), size: int.tryParse(attr('size'))),
      );
    } else if (m.group(3) != null) {
      try {
        parts.add(ImagePart(utf8.decode(base64Url.decode(base64Url.normalize(m.group(3)!)))));
      } on FormatException {
        // A damaged marker: nothing to show.
      }
    } else if (m.group(4) != null) {
      parts.add(PhotosPart(m.group(4)!));
    } else if (m.group(5) != null) {
      try {
        final json = jsonDecode(m.group(5)!.trim()) as Map<String, dynamic>;
        final options = [
          for (final o in json['options'] as List)
            if (o is Map && o['label'] is String)
              (label: o['label'] as String, description: o['description'] as String? ?? ''),
        ];
        if (options.isNotEmpty) parts.add(ChoicesPart(json['question'] as String? ?? '', options));
      } catch (_) {
        // Not valid JSON: leave it out rather than show raw code.
      }
    } else if (m.group(6) != null) {
      final source = m.group(7)!;
      final done = m.group(8)!.isNotEmpty;
      final react = m.group(6) != 'html';
      if (_isApp(source, react: react, done: done)) {
        parts.add(AppPart(source: source.trimRight(), react: react, done: done));
      } else {
        // A code example, not an app: a code card.
        parts.add(CodePart(language: m.group(6)!, code: source.trimRight(), done: done));
      }
    } else if (m.group(9) != null) {
      final language = m.group(9)!;
      if (language.startsWith('garad-')) {
        text(m.group(0)!); // the website's own blocks (steps, links, quiz): as before
      } else {
        // A long example with section comments (# ===== 1. Variables =====): one heading and card each.
        final done = m.group(11)!.isNotEmpty;
        final sections = splitCodeSections(m.group(10)!.trimRight());
        final earlier = <String>[];
        for (final (i, s) in sections.indexed) {
          if (s.title != null) parts.add(TextPart('#### ${s.title}'));
          final last = i == sections.length - 1;
          parts.add(CodePart(language: language, code: s.code, done: !last || done, setup: List.of(earlier)));
          earlier.add(s.code);
        }
      }
    }
  }
  text(content.substring(at));
  return parts;
}

/// A whole page or app (shown as a live preview), not a short code example.
bool _isApp(String source, {required bool react, required bool done}) {
  if (!react) return RegExp(r'<!doctype html|<html', caseSensitive: false).hasMatch(source);
  if (RegExp(r'export\s+default').hasMatch(source)) return true;
  // Still being written: the export usually comes at the end.
  return !done && RegExp(r'''from\s+["']react["']''').hasMatch(source);
}

/// The title of the first app in an answer, or null (for "Version 2" of the same app).
String? appTitleIn(String content) {
  if (!content.contains('```')) return null;
  for (final part in parseAnswer(content)) {
    if (part is AppPart) return part.title;
  }
  return null;
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

/// An assistant answer: text, file cards, images and question cards, plus what the AI is doing now.
class AnswerView extends StatelessWidget {
  const AnswerView({
    super.key,
    required this.message,
    required this.streaming,
    this.onChoose,
    this.chosen,
    this.onEditImage,
    this.onAppChange,
    this.appVersion = 1,
  });

  /// Sends a change the user asked for in an app's preview. Null: the preview has no Ask bar.
  final ValueChanged<String>? onAppChange;

  /// Which version of its app this answer's app is (2 when it rewrites an earlier one).
  final int appVersion;

  /// Opens the Edit screen for one of this answer's images (its address). Null: no Edit.
  final ImageToolHandler? onEditImage;

  final ChatMessage message;
  final bool streaming;

  /// Sends a picked option. Null once the question has been answered.
  final ValueChanged<String>? onChoose;

  /// The user's answer to this message's question (their next message), shown under it.
  final String? chosen;

  @override
  Widget build(BuildContext context) {
    final parts = parseAnswer(message.content);
    final activity = message.activity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final part in parts)
          switch (part) {
            TextPart(:final markdown) => MarkdownBody(
              data: markdown,
              selectable: true,
              styleSheet: serifMarkdown(context),
              onTapLink: (text, href, title) {
                final uri = href == null ? null : Uri.tryParse(href);
                if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            FilePart() => _FileCard(file: part),
            ImagePart(:final url) => _ChatImage(url: url, onEdit: onEditImage),
            PhotosPart(:final query) => PhotoStrip(key: ValueKey('photos:$query'), query: query),
            CodePart() => CodeBlock(language: part.language, code: part.code, done: part.done, setup: part.setup),
            ChoicesPart() => _ChoicesCard(choices: part, onChoose: onChoose, chosen: chosen),
            AppPart() => _AppCard(app: part, version: appVersion, onChange: onAppChange),
          },
        if (streaming && (activity?.working ?? false))
          _Working(status: activity!)
        else if (streaming && parts.isEmpty)
          _Working(
            status: ToolStatus(tool: '', state: 'working', label: chatStrings.thinking),
          ),
      ],
    );
  }
}

// ---- What the AI is doing: a different look for images, documents and text ----

class _Working extends StatelessWidget {
  const _Working({required this.status});

  final ToolStatus status;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    if (status.isImage) {
      // An image placeholder that shimmers until the picture arrives.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox.square(
                dimension: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned.fill(child: _DotWave()),
                    const GaradThinkingLogo(size: 44),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _Shimmer(
              child: Text(chatStrings.creatingImage, style: TextStyle(color: c.muted, fontSize: 14)),
            ),
          ],
        ),
      );
    }
    if (status.isDocument) {
      // A file card in the making.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _CardFrame(
          kind: switch (status.tool) {
            'create_pdf' => 'pdf',
            'create_xlsx' => 'spreadsheet',
            'create_presentation' => 'presentation',
            _ => 'document',
          },
          title: _Shimmer(
            child: Text(
              chatStrings.creatingDocument,
              style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          subtitle: status.label,
        ),
      );
    }
    final search = status.tool.contains('search');
    final label = status.tool == 'web_search'
        ? chatStrings.searchingWeb
        : (status.label.isEmpty ? chatStrings.thinking : status.label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (search) Icon(Icons.travel_explore, size: 17, color: c.muted) else const GaradThinkingLogo(),
          const SizedBox(width: 8),
          _Shimmer(
            child: Text(label, style: TextStyle(color: c.muted, fontSize: 14.5)),
          ),
        ],
      ),
    );
  }
}

/// The Garad logo, gently breathing and tilting while the AI thinks.
class GaradThinkingLogo extends StatefulWidget {
  const GaradThinkingLogo({super.key, this.size = 20});

  final double size;

  @override
  State<GaradThinkingLogo> createState() => _GaradThinkingLogoState();
}

class _GaradThinkingLogoState extends State<GaradThinkingLogo> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);
  late final _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    builder: (context, child) => Opacity(
      opacity: 0.6 + 0.4 * _curve.value, // 0.6 → 1
      child: Transform.rotate(
        angle: (_curve.value - 0.5) * 0.35, // about ±10°
        child: Transform.scale(scale: 0.88 + 0.12 * _curve.value, child: child),
      ),
    ),
    child: Image.asset(
      'assets/images/splash-icon.png',
      width: widget.size,
      height: widget.size,
      semanticLabel: 'Garad AI',
    ),
  );
}

/// An image on its way: a grid of small Garad-purple dots on a soft background, brightening in a wave
/// that rolls from the top left to the bottom right.
class _DotWave extends StatefulWidget {
  const _DotWave();

  @override
  State<_DotWave> createState() => _DotWaveState();
}

class _DotWaveState extends State<_DotWave> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return ColoredBox(
      color: c.brandSoft,
      child: CustomPaint(painter: _DotWavePainter(_controller, c.brand)),
    );
  }
}

class _DotWavePainter extends CustomPainter {
  _DotWavePainter(this.animation, this.color) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  static const _gap = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final diagonal = size.width + size.height;
    for (var y = _gap / 2; y < size.height; y += _gap) {
      for (var x = _gap / 2; x < size.width; x += _gap) {
        // 0 → 1 → 0 as the wave passes this dot.
        final phase = animation.value - (x + y) / diagonal;
        final wave = (math.sin(phase * 2 * math.pi) + 1) / 2;
        paint.color = color.withValues(alpha: 0.12 + 0.5 * wave);
        canvas.drawCircle(Offset(x, y), 1.4 + 0.8 * wave, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotWavePainter old) => old.color != color;
}

/// A light sweep across [child], like Claude's "thinking" text.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});

  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value * 3 - 1; // -1 … 2: the light band crosses the whole width
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            colors: [Colors.transparent, Colors.white.withValues(alpha: 0.55), Colors.transparent],
            stops: [(t - 0.3).clamp(0, 1), t.clamp(0, 1), (t + 0.3).clamp(0, 1)],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

// ---- File card ----

String _size(int bytes) =>
    bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.kind, required this.title, required this.subtitle, this.trailing, this.onTap});

  /// pdf · document · spreadsheet · presentation (the thumbnail's badge).
  final String kind;
  final Widget title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Material(
      color: Theme.of(context).brightness == Brightness.dark ? c.surfaceStrong : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              DocumentThumb(kind: kind),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: c.muted, fontSize: 13)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A PDF / Word / Excel / PowerPoint the AI made: tap to preview it in the app (Share is there).
class _FileCard extends StatelessWidget {
  const _FileCard({required this.file});

  final FilePart file;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final id = GaradApi.documentId(file.url);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _CardFrame(
        kind: file.kind,
        title: Text(
          file.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w500),
        ),
        subtitle: [documentKindLabel(file.kind), if (file.size != null) _size(file.size!)].join(' · '),
        trailing: Icon(Icons.chevron_right, size: 22, color: c.faint),
        onTap: id == null ? null : () => openDocument(context, id, title: file.name),
      ),
    );
  }
}

// ---- Image ----

class _ChatImage extends StatelessWidget {
  const _ChatImage({required this.url, this.onEdit});

  final String url;

  /// Opens the Edit screen for this image (ChatGPT-style). Null: no Edit.
  final ImageToolHandler? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final image = LibraryImage(id: url, url: url, prompt: '');
    final edit = onEdit;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImageViewer(images: [image], onTool: edit == null ? null : (_, tool) => edit(url, tool)),
          ),
        ),
        child: Stack(
          children: [
            _image(c, image),
            // ✎ Edit, on the picture's corner.
            if (edit != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: const StadiumBorder(),
                  elevation: 1,
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => edit(url, ImageTool.edit),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.edit_outlined, size: 16, color: Colors.black87),
                          const SizedBox(width: 6),
                          Text(
                            chatStrings.edit,
                            style: const TextStyle(color: Colors.black87, fontSize: 13.5, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _image(Palette c, LibraryImage image) => Hero(
    tag: image.id,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 360),
        child: Image.network(
          reachableUrl(url),
          // In a browser, draw with an <img> tag if the image host does not allow cross-origin loading.
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          fit: BoxFit.cover,
          frameBuilder: (_, child, frame, _) =>
              frame == null ? const SizedBox.square(dimension: 260, child: _DotWave()) : child,
          errorBuilder: (_, _, _) => Container(
            width: 260,
            height: 160,
            color: c.surfaceStrong,
            child: Icon(Icons.broken_image_outlined, color: c.faint),
          ),
        ),
      ),
    ),
  );
}

// ---- Pictures for an idea (ChatGPT-style) ----

/// A row of web pictures under an idea's heading: one large, two small stacked beside it. Tap one
/// to see them full screen. Shows nothing when no pictures are found, so the answer reads the same.
class PhotoStrip extends StatefulWidget {
  const PhotoStrip({super.key, required this.query});

  final String query;

  /// Where the pictures come from (the signed-in user's API); replaceable in tests.
  @visibleForTesting
  static Future<List<WebPhoto>> Function(BuildContext context, String query) load = (context, query) {
    try {
      return Provider.of<AuthState>(context, listen: false).api.photos(query);
    } catch (_) {
      return Future.value(const <WebPhoto>[]); // no signed-in API here
    }
  };

  @override
  State<PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<PhotoStrip> {
  late Future<List<WebPhoto>> _photos;

  @override
  void initState() {
    super.initState();
    _photos = PhotoStrip.load(context, widget.query);
  }

  @override
  void didUpdateWidget(PhotoStrip old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _photos = PhotoStrip.load(context, widget.query);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WebPhoto>>(
      future: _photos,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // The picture is being made: a shimmering frame its size.
          final c = Palette.of(context);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 3 / 2,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned.fill(child: _DotWave()),
                    _Shimmer(
                      child: Text(chatStrings.creatingImage, style: TextStyle(color: c.muted, fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final photos = (snapshot.data ?? const <WebPhoto>[]).take(3).toList();
        if (photos.isEmpty) return const SizedBox.shrink();
        // One picture (made by the AI): full width, in its own 3:2 shape.
        if (photos.length == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: _PhotoTile(photo: photos[0], onTap: () => _open(0, photos)),
            ),
          );
        }
        Widget tile(int i) => Expanded(child: _PhotoTile(photo: photos[i], onTap: () => _open(i, photos)));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 168,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _PhotoTile(photo: photos[0], onTap: () => _open(0, photos))),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [tile(1), if (photos.length > 2) ...[const SizedBox(height: 4), tile(2)]],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _open(int index, List<WebPhoto> photos) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewer(
          images: [for (final p in photos) LibraryImage(id: 'web:${p.url}', url: reachableUrl(p.url), prompt: p.title)],
          initial: index,
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.onTap});

  final WebPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    Widget empty() => ColoredBox(color: c.surfaceStrong);
    Widget network(String url, Widget Function() onError) => Image.network(
      reachableUrl(url), // the server's own pictures may be addressed as localhost
      fit: BoxFit.cover,
      // In a browser, draw with an <img> tag if the image host does not allow cross-origin loading.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      frameBuilder: (_, child, frame, _) => frame == null ? const _DotWave() : child,
      errorBuilder: (_, _, _) => onError(),
    );
    return Semantics(
      image: true,
      label: photo.title,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          // Some sites refuse other apps: then their small copy, then a plain tile.
          child: network(photo.url, () => photo.thumbnail.isEmpty ? empty() : network(photo.thumbnail, empty)),
        ),
      ),
    );
  }
}

// ---- Question with options (Claude-style) ----

class _ChoicesCard extends StatelessWidget {
  const _ChoicesCard({required this.choices, required this.onChoose, required this.chosen});

  final ChoicesPart choices;
  final ValueChanged<String>? onChoose;
  final String? chosen;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final answered = onChoose == null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? c.surfaceStrong : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (answered) Text(chatStrings.question, style: TextStyle(color: c.muted, fontSize: 13)),
          if (answered) const SizedBox(height: 6),
          Text(
            choices.question,
            style: TextStyle(
              color: answered ? c.muted : c.text,
              fontSize: answered ? 15 : 18,
              fontWeight: answered ? FontWeight.w400 : FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (answered) ...[
            if (chosen != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(chosen!, style: TextStyle(color: c.text, fontSize: 15)),
              ),
          ] else ...[
            const SizedBox(height: 8),
            for (final (i, option) in choices.options.indexed) ...[
              if (i > 0) Divider(height: 1, color: c.line),
              InkWell(
                onTap: () => onChoose!(option.label),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.label,
                              style: TextStyle(color: c.text, fontSize: 15.5, fontWeight: FontWeight.w500),
                            ),
                            if (option.description.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(option.description, style: TextStyle(color: c.muted, fontSize: 13.5)),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: c.faint, size: 20),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// An app or website the AI built, like Claude's artifact card: while the code is written it shows
/// "Writing code · N lines" and the line being written; then tap to run it (Preview / Code).
class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.version, required this.onChange});

  final AppPart app;
  final int version;
  final ValueChanged<String>? onChange;

  Future<void> _open(BuildContext context) async {
    final change = await openAppPreview(context, app, version: version, canAskForChanges: onChange != null);
    if (change != null) onChange?.call(change);
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = chatStrings;
    final kind = app.react ? s.appKind : s.websiteKind;
    final lastLine = app.done
        ? ''
        : app.source.split('\n').lastWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Theme.of(context).brightness == Brightness.dark ? c.surfaceStrong : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: app.done ? () => _open(context) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
                      child: app.done
                          ? Icon(app.react ? Icons.widgets_outlined : Icons.language, color: c.brand, size: 24)
                          : const Center(child: GaradThinkingLogo(size: 24)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (app.done)
                            Text(
                              app.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600),
                            )
                          else
                            _Shimmer(
                              child: Text(
                                s.buildingApp,
                                style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ),
                          const SizedBox(height: 3),
                          Text(
                            app.done
                                ? (version > 1 ? '$kind · ${s.appVersion(version)}' : kind)
                                : s.writingCode(app.lines),
                            style: TextStyle(color: c.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (app.done)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 17, color: c.text),
                            const SizedBox(width: 3),
                            Text(
                              s.preview,
                              style: TextStyle(color: c.text, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (lastLine.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      lastLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: c.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
