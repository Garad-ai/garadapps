import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../chat_strings.dart';
import '../theme.dart';
import 'library_screen.dart';

/// The image tools under a picture (Claude / ChatGPT style).
enum ImageTool {
  /// Describe a change to the whole picture.
  edit,

  /// A new shape: square / portrait / landscape.
  resize,

  /// Paint over a part, then describe what to do there.
  markup,

  /// Paint over something to take it out; the space is filled in naturally.
  remove,
}

/// What an image tool returns: the edit, and the words sent with it (shown in the chat).
typedef ImageEditRequest = ({ImageEdit edit, String instruction});

/// Runs an image tool on the image at this address (the chat sends the result as a message).
typedef ImageToolHandler = void Function(String imageUrl, ImageTool tool);

/// Runs an image tool on an image of the chat; null when closed without sending.
/// Resize is a small sheet of shapes; the other tools open the editor.
Future<ImageEditRequest?> runImageTool(BuildContext context, String imageUrl, ImageTool tool) async {
  if (tool == ImageTool.resize) {
    final size = await _pickShape(context);
    if (size == null) return null;
    return (
      edit: ImageEdit(imageUrl: imageUrl, size: size),
      instruction: chatStrings.reshapeAsk.replaceAll('{shape}', shapeLabel(size).toLowerCase()),
    );
  }
  return Navigator.of(context).push<ImageEditRequest>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageEditScreen(imageUrl: imageUrl, tool: tool),
    ),
  );
}

/// The shape's name: Square / Portrait / Landscape.
String shapeLabel(String size) => switch (size) {
  '1024x1536' => chatStrings.portrait,
  '1536x1024' => chatStrings.landscape,
  _ => chatStrings.square,
};

/// Resize: Square · Portrait · Landscape.
Future<String?> _pickShape(BuildContext context) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  builder: (sheet) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (size, icon) in const [
          ('1024x1024', Icons.crop_square),
          ('1024x1536', Icons.crop_portrait),
          ('1536x1024', Icons.crop_landscape),
        ])
          ListTile(leading: Icon(icon), title: Text(shapeLabel(size)), onTap: () => Navigator.pop(sheet, size)),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

/// Edit / Markup / Remove: the picture (with a brush for Markup and Remove), and what to change.
class ImageEditScreen extends StatefulWidget {
  const ImageEditScreen({super.key, required this.imageUrl, this.tool = ImageTool.edit});

  final String imageUrl;
  final ImageTool tool;

  @override
  State<ImageEditScreen> createState() => _ImageEditScreenState();
}

class _ImageEditScreenState extends State<ImageEditScreen> {
  final _text = TextEditingController();
  final _imageKey = GlobalKey();

  /// Brush strokes, in the picture's own pixels.
  final List<List<Offset>> _strokes = [];
  bool _sending = false;
  bool _loaded = false;

  bool get _brush => widget.tool != ImageTool.edit;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The picture's size in its own pixels (the brush paints in these), once it has loaded.
  Size? get _imageSize {
    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize && !box.size.isEmpty ? box.size : null;
  }

  double get _brushWidth => (_imageSize?.shortestSide ?? 1024) / 14;

  bool get _canSend =>
      !_sending &&
      switch (widget.tool) {
        // Remove needs the painted object; words are optional.
        ImageTool.remove => _strokes.isNotEmpty,
        // Markup needs both: where, and what.
        ImageTool.markup => _strokes.isNotEmpty && _text.text.trim().isNotEmpty,
        _ => _text.text.trim().isNotEmpty,
      };

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _sending = true);
    final size = _imageSize;
    final mask = _strokes.isEmpty || size == null ? null : await editMask(size, _strokes, _brushWidth);
    if (!mounted) return;
    final typed = _text.text.trim();
    Navigator.pop<ImageEditRequest>(context, (
      edit: ImageEdit(imageUrl: widget.imageUrl, mask: mask),
      instruction: widget.tool == ImageTool.remove && typed.isEmpty ? chatStrings.removeAsk : typed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final (title, hint) = switch (widget.tool) {
      ImageTool.markup => (chatStrings.markup, chatStrings.markupHint),
      ImageTool.remove => (chatStrings.remove, chatStrings.removeHint),
      _ => (chatStrings.edit, chatStrings.editHint),
    };
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          if (_brush) ...[
            IconButton(
              tooltip: chatStrings.undo,
              icon: const Icon(Icons.undo),
              onPressed: _strokes.isEmpty ? null : () => setState(_strokes.removeLast),
            ),
            IconButton(
              tooltip: chatStrings.clearSelection,
              icon: const Icon(Icons.layers_clear_outlined),
              onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
            ),
            // The picture, with the brush on it (in the picture's own pixels).
            Expanded(
              child: Center(
                child: FittedBox(
                  child: Stack(
                    key: _imageKey,
                    children: [
                      Image.network(
                        reachableUrl(widget.imageUrl),
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        frameBuilder: (_, child, frame, _) {
                          // Loaded (once): rebuild so the brush knows the picture's size.
                          if (frame != null && !_loaded) {
                            _loaded = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() {});
                            });
                          }
                          return child;
                        },
                        errorBuilder: (_, _, _) => const SizedBox.square(
                          dimension: 300,
                          child: Icon(Icons.broken_image_outlined, color: Colors.white38),
                        ),
                      ),
                      if (_brush)
                        Positioned.fill(
                          child: GestureDetector(
                            key: const ValueKey('image-brush'),
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                            onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                            child: CustomPaint(painter: _StrokesPainter(_strokes, _brushWidth, c.brand)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // What to change + send.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        autofocus: widget.tool == ImageTool.edit,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          hintText: widget.tool == ImageTool.remove
                              ? chatStrings.removeOptional
                              : chatStrings.describeEdit,
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 16),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: title,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white38,
                      ),
                      onPressed: _canSend ? _send : null,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
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

/// The painted area: soft Garad-purple strokes over the picture.
class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes, this.width, this.color);

  final List<List<Offset>> strokes;
  final double width;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Solid strokes on one layer, and the whole layer see-through: overlaps stay one even colour.
    canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: 0.5));
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, width / 2, Paint()..color = color);
      } else {
        canvas.drawPath(Path()..addPolygon(stroke, false), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokesPainter old) => true;
}

/// The painted area as an edit mask (PNG, [size] = the picture's pixels): opaque everywhere,
/// transparent along the [strokes] — the image AI changes only the transparent part.
Future<Uint8List?> editMask(Size size, List<List<Offset>> strokes, double brush) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
  final eraser = Paint()
    ..blendMode = BlendMode.clear
    ..style = PaintingStyle.stroke
    ..strokeWidth = brush
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (final stroke in strokes) {
    if (stroke.length == 1) {
      canvas.drawCircle(stroke.first, brush / 2, Paint()..blendMode = BlendMode.clear);
    } else {
      canvas.drawPath(Path()..addPolygon(stroke, false), eraser);
    }
  }
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png?.buffer.asUint8List();
}
