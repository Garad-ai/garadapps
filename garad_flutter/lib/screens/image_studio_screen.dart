import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';
import 'billing_screen.dart';
import 'library_screen.dart';

/// The AI Toolkit's Image Generator, as an app screen (garad.ai's ImageGenerator.tsx): the user's images
/// in a grid, and at the bottom a clean box — the prompt, a reference photo for models that take one, and
/// chips for the model, how many, style, lighting and mood. Generating, plan locks, credits and storage
/// are the website's own (POST /toolkit/images); the images stay in the user's account.
class ImageStudioScreen extends StatefulWidget {
  const ImageStudioScreen({super.key});

  @override
  State<ImageStudioScreen> createState() => _ImageStudioScreenState();
}

class _ImageStudioScreenState extends State<ImageStudioScreen> {
  final _prompt = TextEditingController();
  List<ImageModelInfo> _models = const [];
  ImageModelInfo? _model;
  final List<ToolkitImage> _images = [];
  int? _nextPage;
  bool _loading = true;
  bool _generating = false;
  String? _error;

  int _count = 1;
  String _style = '';
  String _lighting = '';
  String _mood = '';
  Uint8List? _reference;

  GaradApi get _api => context.read<AuthState>().api;

  static String _t(String so, String en) => chatStrings.isSomali ? so : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([_api.imageModels(), _api.toolkitImages()]);
      final models = results[0] as List<ImageModelInfo>;
      final page = results[1] as ({List<ToolkitImage> items, int? nextPage});
      if (!mounted) return;
      setState(() {
        // Open models first (as the website's picker), locked ones after with Upgrade.
        _models = [...models.where((m) => m.usable), ...models.where((m) => !m.usable)];
        _model = _models.where((m) => m.usable).firstOrNull ?? _models.firstOrNull;
        _images
          ..clear()
          ..addAll(page.items);
        _nextPage = page.nextPage;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final next = _nextPage;
    if (next == null) return;
    _nextPage = null;
    try {
      final page = await _api.toolkitImages(page: next);
      if (mounted) {
        setState(() {
          _images.addAll(page.items);
          _nextPage = page.nextPage;
        });
      }
    } on ApiException {
      _nextPage = next;
    }
  }

  Future<void> _generate() async {
    final model = _model;
    final text = _prompt.text.trim();
    if (model == null || text.isEmpty || _generating) return;
    if (model.locked) return _upgrade();
    FocusScope.of(context).unfocus();
    setState(() => _generating = true);
    try {
      final made = await _api.generateImages(
        model: model,
        prompt: text,
        count: _count,
        style: _style,
        lighting: _lighting,
        mood: _mood,
        reference: model.takesReference ? _reference : null,
      );
      if (!mounted) return;
      setState(() => _images.insertAll(0, made));
    } on ApiException catch (e) {
      if (!mounted) return;
      _snack(e.message, upgrade: e.statusCode == 402 || e.statusCode == 403);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _snack(String text, {bool upgrade = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: upgrade ? SnackBarAction(label: _t('Kor u qaad', 'Upgrade'), onPressed: _upgrade) : null,
      ),
    );
  }

  void _upgrade() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BillingScreen()));

  Future<void> _pickReference() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _reference = bytes);
  }

  void _open(int index) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ImageViewer(
        images: [
          for (final i in _images) LibraryImage(id: i.slug, url: i.url, prompt: i.prompt, createdAt: i.createdAt),
        ],
        initial: index,
      ),
    ),
  );

  Future<void> _delete(ToolkitImage image) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListTile(
          leading: Icon(Icons.delete_outline, color: Palette.of(sheet).danger),
          title: Text(_t('Tirtir sawirka', 'Delete image'), style: TextStyle(color: Palette.of(sheet).danger)),
          onTap: () => Navigator.pop(sheet, true),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final index = _images.indexOf(image);
    setState(() => _images.remove(image));
    try {
      await _api.deleteToolkitImage(image.slug);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _images.insert(index.clamp(0, _images.length), image));
      _snack(e.message);
    }
  }

  // ---- Option pickers (bottom sheets) ----

  Future<void> _pickModel() async {
    final picked = await _choose<ImageModelInfo>(
      title: _t('Moodeelka', 'Model'),
      items: _models,
      label: (m) => m.name,
      // garad.ai marks a model "unavailable" when the account has no credits left for it.
      badge: (m) => m.locked ? (m.requiredPlan ?? _t('Kor u qaad', 'Upgrade')) : (!m.available ? _t('Credit ma jiro', 'No credits') : null),
      selected: _model,
    );
    if (picked == null) return;
    if (picked.locked) return _upgrade();
    if (!picked.available) {
      return _snack(
        _t('Credit kuguma haro moodeelkan. Kor u qaad qorshahaaga.', 'You have no credits left for this model. Upgrade to get more.'),
        upgrade: true,
      );
    }
    setState(() => _model = picked);
  }

  Future<void> _pickOption(String title, List<String> values, String current, ValueChanged<String> set) async {
    final picked = await _choose<String>(
      title: title,
      items: ['', ...values],
      label: (v) => v.isEmpty ? _t('Midna', 'None') : ImageOptions.label(v),
      selected: current,
    );
    if (picked != null) setState(() => set(picked));
  }

  Future<T?> _choose<T>({
    required String title,
    required List<T> items,
    required String Function(T) label,
    String? Function(T)? badge,
    T? selected,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) {
        final c = Palette.of(sheet);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(title, style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                for (final item in items)
                  Builder(
                    builder: (_) {
                      final b = badge?.call(item);
                      return ListTile(
                        title: Text(label(item), style: TextStyle(color: c.text, fontSize: 16)),
                        trailing: b != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(8)),
                                child: Text(b, style: TextStyle(color: c.brand, fontSize: 12.5)),
                              )
                            : (item == selected ? Icon(Icons.check, color: c.brand) : null),
                        onTap: () => Navigator.pop(sheet, item),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Layout ----

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _t('Sawir & Fiidiyow', 'Image Generator'),
          style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _gallery(c)),
            Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), child: _composer(c)),
          ],
        ),
      ),
    );
  }

  Widget _gallery(Palette c) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
              TextButton(onPressed: _load, child: Text(chatStrings.retry)),
            ],
          ),
        ),
      );
    }
    final tiles = _generating ? _count : 0;
    if (_images.isEmpty && tiles == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 40, color: c.brand),
              const SizedBox(height: 12),
              Text(
                _t('Sharax sawirka aad rabto', 'Describe the image you want'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _t('Sawirradaadu halkan ayay ka muuqan doonaan.', 'Your images will appear here.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: tiles + _images.length,
        itemBuilder: (context, i) {
          if (i < tiles) return _Making(label: _t('Waa la sameynayaa…', 'Creating…'));
          final image = _images[i - tiles];
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: c.surfaceStrong,
              child: InkWell(
                onTap: () => _open(i - tiles),
                onLongPress: () => _delete(image),
                child: image.pending
                    ? _Making(label: _t('Waa la sameynayaa…', 'Creating…'))
                    : Image.network(
                        reachableUrl(image.url),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: c.faint),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _composer(Palette c) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final model = _model;
    Widget chip(String text, VoidCallback onTap, {bool active = false, IconData? icon}) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        onPressed: _generating ? null : onTap,
        avatar: icon == null ? null : Icon(icon, size: 16, color: active ? c.brand : c.muted),
        label: Text(text, style: TextStyle(color: active ? c.brand : c.text, fontSize: 13.5)),
        backgroundColor: active ? c.brandSoft : c.surfaceStrong,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: dark ? c.surfaceStrong : Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: dark ? Border.all(color: c.line) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.25 : 0.08), blurRadius: 18, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                chip(model?.name ?? _t('Moodeel', 'Model'), _pickModel, icon: Icons.auto_awesome_outlined),
                chip(
                  '$_count ${_count == 1 ? _t('sawir', 'image') : _t('sawir', 'images')}',
                  () => setState(() => _count = _count % 4 + 1),
                ),
                chip(_style.isEmpty ? _t('Qaab', 'Style') : ImageOptions.label(_style), () {
                  _pickOption(_t('Qaab', 'Style'), ImageOptions.styles, _style, (v) => _style = v);
                }, active: _style.isNotEmpty),
                chip(_lighting.isEmpty ? _t('Iftiin', 'Lighting') : ImageOptions.label(_lighting), () {
                  _pickOption(_t('Iftiin', 'Lighting'), ImageOptions.lightings, _lighting, (v) => _lighting = v);
                }, active: _lighting.isNotEmpty),
                chip(_mood.isEmpty ? _t('Dareen', 'Mood') : ImageOptions.label(_mood), () {
                  _pickOption(_t('Dareen', 'Mood'), ImageOptions.moods, _mood, (v) => _mood = v);
                }, active: _mood.isNotEmpty),
              ],
            ),
          ),
          if (_reference != null && (model?.takesReference ?? false))
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_reference!, width: 60, height: 60, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: GestureDetector(
                        onTap: () => setState(() => _reference = null),
                        child: CircleAvatar(radius: 11, backgroundColor: c.text, child: Icon(Icons.close, size: 13, color: c.background)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // A reference photo, for models that take one (edits, "in this style").
              if (model?.takesReference ?? false)
                IconButton(
                  tooltip: _t('Ku dar sawir', 'Add a reference photo'),
                  onPressed: _generating ? null : _pickReference,
                  icon: Icon(Icons.add_photo_alternate_outlined, size: 25, color: c.text),
                )
              else
                const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _prompt,
                  enabled: !_generating,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: c.text, fontSize: 16.5),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: _t('Sharax sawirka…', 'Describe an image…'),
                    hintStyle: TextStyle(color: c.faint, fontSize: 16.5),
                    contentPadding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _prompt,
                  builder: (context, value, _) {
                    final ready = value.text.trim().isNotEmpty && model != null && !_generating;
                    return Material(
                      color: ready ? c.brand : c.surfaceStrong,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: ready ? _generate : null,
                        child: SizedBox.square(
                          dimension: 44,
                          child: Center(
                            child: _generating
                                ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: c.brand))
                                : Icon(Icons.arrow_upward_rounded, size: 22, color: ready ? Colors.white : c.faint),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tile while an image is being made: a soft pulse and "Creating…".
class _Making extends StatefulWidget {
  const _Making({required this.label});

  final String label;

  @override
  State<_Making> createState() => _MakingState();
}

class _MakingState extends State<_Making> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Color.lerp(c.surfaceStrong, c.brandSoft, _pulse.value),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, color: c.brand),
              const SizedBox(height: 8),
              Text(widget.label, style: TextStyle(color: c.muted, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
