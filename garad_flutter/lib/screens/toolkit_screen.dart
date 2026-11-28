import 'package:flutter/material.dart';

import '../chat_strings.dart';
import '../theme.dart';

/// garad.ai's AI Toolkit (paid plans), as app screens: Image & Video Generator, Audio Studio and Social
/// Media. Shown in place of the chat when the top bar's switch is on "AI Toolkit".
class ToolkitScreen extends StatelessWidget {
  const ToolkitScreen({super.key, this.onOpenTool});

  /// Opens a tool ("image", "video", "audio", "social"); null while a tool is not built yet.
  final ValueChanged<String>? onOpenTool;

  static String _t(String so, String en) => chatStrings.isSomali ? so : en;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final tools = [
      (
        id: 'image',
        icon: Icons.image_outlined,
        title: _t('Sawir & Fiidiyow', 'Image & Video Generator'),
        body: _t(
          'Ka samee sawirro iyo fiidiyowyo qoraal ama sawir.',
          'Create images and videos from a description or a photo.',
        ),
      ),
      (
        id: 'audio',
        icon: Icons.mic_none_rounded,
        title: _t('Istuudiyaha Codka', 'Audio Studio'),
        body: _t('Qoraal u beddel cod dabiici ah.', 'Turn text into natural speech and audio.'),
      ),
      (
        id: 'social',
        icon: Icons.auto_awesome_outlined,
        title: _t('Baraha Bulshada', 'Social Media'),
        body: _t(
          'Qor oo diyaari qoraallada baraha bulshada.',
          'Write and plan posts for your social media.',
        ),
      ),
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          _t('Qalabka AI', 'AI Toolkit'),
          style: TextStyle(color: c.text, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6),
        ),
        const SizedBox(height: 6),
        Text(
          _t('Qalab abuur oo dhammaantood hal meel ku jira.', 'Creative tools, all in one place.'),
          style: TextStyle(color: c.muted, fontSize: 15),
        ),
        const SizedBox(height: 20),
        for (final tool in tools) ...[
          Material(
            color: dark ? c.surfaceStrong : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: c.line)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpenTool == null ? null : () => onOpenTool!(tool.id),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(16)),
                      child: Icon(tool.icon, color: c.brand, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tool.title, style: TextStyle(color: c.text, fontSize: 17, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(tool.body, style: TextStyle(color: c.muted, fontSize: 14, height: 1.35)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: c.faint),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
