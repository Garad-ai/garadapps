import 'package:flutter/material.dart';

import '../api/models.dart';
import '../chat_strings.dart';
import '../theme.dart';

/// "Select model", Claude-style: the Claude models in one card (name, badge, one-line description, ✓),
/// then "More models ›" for the other providers. Returns the chosen model id, or null.
Future<String?> showModelPicker(BuildContext context, {required List<ChatModelInfo> models, String? selectedId}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Palette.of(context).background,
    builder: (_) => _ModelPicker(models: models, selectedId: selectedId),
  );
}

bool _isClaude(ChatModelInfo m) => m.provider.toLowerCase() == 'anthropic';

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, required this.selectedId});

  final List<ChatModelInfo> models;
  final String? selectedId;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  late final List<ChatModelInfo> _claude = widget.models.where(_isClaude).toList();
  late final List<ChatModelInfo> _others = widget.models.where((m) => !_isClaude(m)).toList();

  /// Showing the "More models" page — only after tapping "More models" (or when there is no Claude model).
  late bool _more = _claude.isEmpty;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = chatStrings;
    final list = _more ? _others : _claude;
    // The chosen model when it is one of the "more" models, shown on the "More models" row.
    final otherPicked = _others.where((m) => m.id == widget.selectedId).firstOrNull;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        // "More models" slides in from the right, like a next screen; back slides it out.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) {
            final incomingMore = child.key == const ValueKey('more');
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(incomingMore ? 1 : -1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
          child: ListView(
            key: ValueKey(_more ? 'more' : 'main'),
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              // ✕ (or ‹ on "More models") · title
              Row(
                children: [
                  _RoundButton(
                    icon: _more && _claude.isNotEmpty ? Icons.arrow_back : Icons.close,
                    tooltip: _more && _claude.isNotEmpty ? s.back : s.close,
                    onTap: () => _more && _claude.isNotEmpty ? setState(() => _more = false) : Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      _more ? s.moreModels : s.selectModel,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 16),
              _Card(
                children: [
                  for (final m in list)
                    _ModelRow(
                      model: m,
                      tagline: _tagline(m),
                      selected: m.id == widget.selectedId,
                      onTap: () => Navigator.pop(context, m.id),
                    ),
                ],
              ),
              if (!_more && _others.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Card(
                  children: [
                    ListTile(
                      title: Text(s.moreModels, style: TextStyle(color: c.text, fontSize: 15)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (otherPicked != null)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                otherPicked.shortName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.muted, fontSize: 14),
                              ),
                            ),
                          Icon(Icons.chevron_right, color: c.faint),
                        ],
                      ),
                      onTap: () => setState(() => _more = true),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// A one-line description: what the Claude family is for, else the website's provider/credits line.
  String _tagline(ChatModelInfo m) {
    final s = chatStrings;
    final id = m.id.toLowerCase();
    if (_isClaude(m)) {
      if (id.contains('fable')) return s.tagFable;
      if (id.contains('opus')) return s.tagOpus;
      if (id.contains('sonnet')) return s.tagSonnet;
      if (id.contains('haiku')) return s.tagHaiku;
    }
    return m.description ?? m.provider;
  }
}

/// A white rounded card with thin dividers between its rows.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? c.surfaceStrong : Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: c.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model, required this.tagline, required this.selected, required this.onTap});

  final ChatModelInfo model;
  final String tagline;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = chatStrings;
    // A badge like Claude's plan badge: "Upgrade" for a model outside the plan, "No credits" when empty.
    final badge = model.locked ? s.upgrade : (!model.available ? s.noCredits : null);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          model.shortName.replaceFirst(RegExp(r'^Claude\s+'), ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: model.usable ? c.text : c.muted,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(6)),
                          child: Text(badge, style: TextStyle(color: c.brand, fontSize: 11)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tagline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (selected) ...[const SizedBox(width: 12), Icon(Icons.check, color: c.brand, size: 22)],
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(side: BorderSide(color: c.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(dimension: 40, child: Icon(icon, size: 20, color: c.text)),
        ),
      ),
    );
  }
}
