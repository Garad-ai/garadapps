import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';

/// Opens a created document's preview as a sheet over the chat, like Claude.
Future<void> openDocument(BuildContext context, int id, {String? title}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => DocumentScreen(id: id, title: title),
  ),
);

/// Claude-style document preview: the document as a page (serif title and headings), with Share
/// (the real PDF / Word / Excel file) at the top.
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.id, this.title});

  final int id;

  /// Shown while the document loads.
  final String? title;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  LibraryFile? _doc;
  String? _error;
  bool _sharing = false;

  GaradApi get _api => context.read<AuthState>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final doc = await _api.document(widget.id);
      if (mounted) setState(() => _doc = doc);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final bytes = await _api.downloadDocument(widget.id);
      final name = _doc?.name.isNotEmpty == true ? _doc!.name : 'garad-document';
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: name)]));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final doc = _doc;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.text),
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              style: IconButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.text),
              tooltip: chatStrings.share,
              onPressed: _sharing || doc == null ? null : _share,
              icon: _sharing
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
            ),
          ),
        ],
      ),
      body: doc == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: TextStyle(color: c.muted)),
                        TextButton(onPressed: _load, child: Text(chatStrings.retry)),
                      ],
                    ),
            )
          : _page(doc, c),
    );
  }

  Widget _page(LibraryFile doc, Palette c) {
    final date = doc.createdAt;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      children: [
        Text(
          doc.title,
          style: TextStyle(fontFamily: serifFont, color: c.text, fontSize: 34, height: 1.2),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(icon: documentIcon(doc.kind), label: documentKindLabel(doc.kind)),
            if (date != null)
              _Chip(
                icon: Icons.calendar_today_outlined,
                label: MaterialLocalizations.of(context).formatMediumDate(date),
              ),
          ],
        ),
        const SizedBox(height: 24),
        MarkdownBody(
          data: doc.content ?? doc.excerpt ?? '',
          selectable: true,
          onTapLink: (text, href, title) {
            final uri = href == null ? null : Uri.tryParse(href);
            if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          styleSheet: serifMarkdown(context, document: true),
        ),
        // An older document only has a short excerpt: the full file is behind Share.
        if (doc.content == null) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _sharing ? null : _share,
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(chatStrings.openFile),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.surfaceStrong, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.muted),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: c.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

/// A small page with faint text lines and a coloured type badge (PDF / DOC / XLS / PPT), like a file
/// thumbnail. Used by the chat's file cards and the Library.
class DocumentThumb extends StatelessWidget {
  const DocumentThumb({super.key, required this.kind});

  /// pdf · document · spreadsheet · presentation
  final String kind;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (badge, color) = documentBadge(kind);
    Widget line(double width) => Container(
      width: width,
      height: 2.5,
      margin: const EdgeInsets.only(bottom: 3.5),
      decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
    );
    return Container(
      width: 42,
      height: 52,
      padding: const EdgeInsets.fromLTRB(7, 8, 7, 6),
      decoration: BoxDecoration(
        color: dark ? c.surface : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      // A stack, not a column: the badge sits on the page's bottom edge whatever the text size.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [line(26), line(20), line(24)]),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              child: Text(
                badge,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A document kind's short label and colour: PDF red, DOC blue, XLS green, PPT orange.
(String, Color) documentBadge(String kind) => switch (kind) {
  'pdf' => ('PDF', const Color(0xFFE5484D)),
  'spreadsheet' => ('XLS', const Color(0xFF1E8E3E)),
  'presentation' => ('PPT', const Color(0xFFE8710A)),
  _ => ('DOC', const Color(0xFF2B5BD7)),
};

/// The icon and name of a document kind (shared with the chat's file cards and the Library).
IconData documentIcon(String kind) => switch (kind) {
  'pdf' => Icons.picture_as_pdf_outlined,
  'spreadsheet' => Icons.table_chart_outlined,
  'presentation' => Icons.slideshow_outlined,
  _ => Icons.description_outlined,
};

String documentKindLabel(String kind) => switch (kind) {
  'pdf' => 'PDF',
  'spreadsheet' => 'Excel',
  'presentation' => 'PowerPoint',
  'document' => 'Word',
  _ => kind.toUpperCase(),
};
