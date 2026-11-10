import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../save_image.dart';
import '../theme.dart';
import 'document_screen.dart';
import 'image_edit_screen.dart';

enum _Filter { all, images, documents }

/// Library (Photos / ChatGPT style): everything the user created in chats as one grid of rounded
/// tiles, filtered by the pills at the top (All · Images · Documents) and the search bar at the
/// bottom. Images open full screen; documents open the in-app preview; ＋ starts a new chat.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onOpenChat, this.onNewChat});

  final ValueChanged<int> onOpenChat;

  /// The ＋ button next to the search bar. Null hides it.
  final VoidCallback? onNewChat;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<LibraryImage>? _images;
  List<LibraryFile> _files = const [];
  String? _error;
  var _filter = _Filter.all;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final library = await context.read<AuthState>().api.library();
      if (mounted) {
        setState(() {
          _images = library.images;
          _files = library.files;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// The tiles to show: images and documents mixed, newest first, matching the filter and search.
  List<Object> get _items {
    final query = _search.text.trim().toLowerCase();
    final items = <({Object item, DateTime? at})>[
      if (_filter != _Filter.documents)
        for (final image in _images ?? const <LibraryImage>[])
          if (query.isEmpty || image.prompt.toLowerCase().contains(query)) (item: image, at: image.createdAt),
      if (_filter != _Filter.images)
        for (final file in _files)
          if (query.isEmpty || file.title.toLowerCase().contains(query)) (item: file, at: file.createdAt),
    ]..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return [for (final entry in items) entry.item];
  }

  void _openImage(LibraryImage image) {
    final images = _images!;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewer(
          images: images,
          initial: images.indexOf(image),
          onOpenChat: (id) {
            Navigator.of(context)
              ..pop()
              ..pop();
            widget.onOpenChat(id);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.text),
            icon: const Icon(Icons.chevron_left),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          chatStrings.library,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: c.text),
        ),
      ),
      body: _images == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : _Empty(icon: Icons.cloud_off, text: _error!, onRetry: _load),
            )
          : Stack(
              children: [
                Column(
                  children: [
                    _filters(c),
                    Expanded(child: _grid(c)),
                  ],
                ),
                Positioned(left: 16, right: 16, bottom: 0, child: SafeArea(top: false, child: _bottomBar(c))),
              ],
            ),
    );
  }

  /// All · Images · Documents pills.
  Widget _filters(Palette c) {
    final labels = {
      _Filter.all: chatStrings.all,
      _Filter.images: chatStrings.images,
      _Filter.documents: chatStrings.documents,
    };
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final MapEntry(key: filter, value: label) in labels.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: _filter == filter ? c.text : c.surfaceStrong,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => setState(() => _filter = filter),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: _filter == filter ? c.background : c.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(Palette c) {
    final items = _items;
    if (items.isEmpty) {
      return _Empty(
        icon: _filter == _Filter.documents ? Icons.description_outlined : Icons.photo_library_outlined,
        text: _filter == _Filter.documents ? chatStrings.documentsEmpty : chatStrings.libraryEmpty,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        // Room at the bottom for the floating search bar.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => switch (items[i]) {
          final LibraryImage image => _ImageTile(image: image, onTap: () => _openImage(image)),
          final LibraryFile file => _DocumentTile(
            file: file,
            onTap: () => openDocument(context, file.id, title: file.title),
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  /// A floating search pill and a round ＋ (new chat), like Photos.
  Widget _bottomBar(Palette c) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shadow = [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4))];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: dark ? c.surfaceStrong : Colors.white,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: c.line),
                boxShadow: shadow,
              ),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                style: TextStyle(color: c.text, fontSize: 16),
                decoration: InputDecoration(
                  hintText: chatStrings.searchLibrary,
                  hintStyle: TextStyle(color: c.faint, fontSize: 16),
                  prefixIcon: Icon(Icons.search, color: c.muted),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, size: 18, color: c.muted),
                          onPressed: () => setState(_search.clear),
                        ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          if (widget.onNewChat != null) ...[
            const SizedBox(width: 10),
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: shadow),
              child: IconButton.filled(
                tooltip: chatStrings.newChat,
                style: IconButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: Colors.white,
                  fixedSize: const Size(50, 50),
                ),
                icon: const Icon(Icons.add),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onNewChat!();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.image, required this.onTap});

  final LibraryImage image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: image.id,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            reachableUrl(image.url),
            // In a browser, draw with an <img> tag if the image host does not allow cross-origin loading.
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            fit: BoxFit.cover,
            cacheWidth: 500,
            errorBuilder: (_, _, _) => ColoredBox(
              color: c.surfaceStrong,
              child: Icon(Icons.broken_image_outlined, color: c.faint),
            ),
            frameBuilder: (_, child, frame, _) => frame == null ? ColoredBox(color: c.surfaceStrong) : child,
          ),
        ),
      ),
    );
  }
}

/// A document as a page: its title in the serif, faint text lines, and the type badge.
class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.file, required this.onTap});

  final LibraryFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget line(double widthFactor) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 4,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
      ),
    );
    return Material(
      color: dark ? c.surfaceStrong : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: serifFont, color: c.text, fontSize: 16, height: 1.25),
              ),
              const SizedBox(height: 12),
              line(1),
              line(0.9),
              line(0.95),
              line(0.6),
              const Spacer(),
              Row(
                children: [
                  _Badge(kind: file.kind),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.createdAt == null ? '' : MaterialLocalizations.of(context).formatShortDate(file.createdAt!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
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

/// PDF / DOC / XLS / PPT in its colour.
class _Badge extends StatelessWidget {
  const _Badge({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final (label, color) = documentBadge(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.3),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.faint),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 14),
            ),
            if (onRetry != null) TextButton(onPressed: onRetry, child: Text(chatStrings.retry)),
          ],
        ),
      ),
    );
  }
}

/// Full-screen image, Claude / ChatGPT style: ✕ · ⋯ (open chat) · Save · Share on top, the picture
/// (swipe, pinch to zoom) and, for images in a chat, the tools underneath: Edit · Resize · Markup · Remove.
class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, required this.images, this.initial = 0, this.onOpenChat, this.onTool});

  final List<LibraryImage> images;
  final int initial;
  final ValueChanged<int>? onOpenChat;

  /// An image tool on the picture shown (the viewer closes first). Null: no tools.
  final void Function(LibraryImage image, ImageTool tool)? onTool;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  /// 'save' or 'share' while it runs.
  String? _busy;

  LibraryImage get _image => widget.images[_index];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// The picture's file name and bytes.
  Future<(String, Uint8List)> _download() async {
    final url = reachableUrl(_image.url);
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    final name = Uri.parse(url).pathSegments.lastOrNull ?? 'garad-image.png';
    return (name, response.bodyBytes);
  }

  Future<void> _run(String what, Future<void> Function() action, String failed) async {
    setState(() => _busy = what);
    try {
      await action();
    } catch (_) {
      _snack(failed);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() => _run('save', () async {
    final (name, bytes) = await _download();
    await saveImage(bytes, name);
    _snack(chatStrings.saved);
  }, chatStrings.saveFailed);

  Future<void> _share() => _run('share', () async {
    final (name, bytes) = await _download();
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: name)]));
  }, chatStrings.cannotConnect);

  /// ⋯ : more (open the chat the image is from).
  Future<void> _more() async {
    final chatId = _image.chatId;
    final open = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: Text(chatStrings.openChat),
          onTap: () => Navigator.pop(sheet, true),
        ),
      ),
    );
    if (open == true && chatId != null && mounted) widget.onOpenChat!(chatId);
  }

  void _tool(ImageTool tool) {
    Navigator.pop(context);
    widget.onTool!(_image, tool);
  }

  @override
  Widget build(BuildContext context) {
    final canOpenChat = widget.onOpenChat != null && _image.chatId != null;
    Widget round(IconData icon, String tooltip, VoidCallback? onTap, {bool busy = false}) => Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF2C2C2E),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ✕ · · · ⋯ · Save · Share
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  round(
                    Icons.close,
                    MaterialLocalizations.of(context).closeButtonTooltip,
                    () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (canOpenChat) ...[round(Icons.more_horiz, chatStrings.more, _more), const SizedBox(width: 8)],
                  round(
                    Icons.file_download_outlined,
                    chatStrings.save,
                    _busy == null ? _save : null,
                    busy: _busy == 'save',
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy == null ? _share : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white70,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      minimumSize: const Size(0, 40),
                    ),
                    child: _busy == 'share'
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text(chatStrings.share, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: Hero(
                      tag: widget.images[i].id,
                      child: Image.network(
                        reachableUrl(widget.images[i].url),
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_image.prompt.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Text(
                  _image.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 13.5),
                ),
              ),
            // Edit · Resize · Markup · Remove
            if (widget.onTool != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final (tool, icon, label) in [
                      (ImageTool.edit, Icons.auto_fix_high_outlined, chatStrings.edit),
                      (ImageTool.resize, Icons.crop_free, chatStrings.resize),
                      (ImageTool.markup, Icons.draw_outlined, chatStrings.markup),
                      (ImageTool.remove, Icons.cleaning_services_outlined, chatStrings.remove),
                    ])
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _tool(tool),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(color: Color(0xFF2C2C2E), shape: BoxShape.circle),
                                child: Icon(icon, color: Colors.white, size: 22),
                              ),
                              const SizedBox(height: 6),
                              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Image links from a local copy of the website say "localhost"; point them at the API's host
/// so they load on the Android emulator (10.0.2.2) or a phone on this PC's network.
String reachableUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.host != 'localhost' && uri.host != '127.0.0.1')) return url;
  final api = Uri.parse(apiBaseUrl);
  return uri.replace(scheme: api.scheme, host: api.host, port: api.hasPort ? api.port : null).toString();
}
