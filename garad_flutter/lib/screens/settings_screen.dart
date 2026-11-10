import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';

const String _privacyUrl = String.fromEnvironment('PRIVACY_URL');

/// Settings, Claude-style: ✕ · "Settings" · ⓘ, the account card, Account / App rows,
/// Appearance (Light / Dark / System) and Log out.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.onOpenScheduled});

  final VoidCallback onOpenScheduled;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = chatStrings;
    final user = context.watch<AuthState>().user;
    final app = context.watch<AppState>();

    void soon() => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.comingSoon)));

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                _RoundButton(icon: Icons.close, tooltip: s.close, onTap: () => Navigator.pop(context)),
                Expanded(
                  child: Text(
                    s.settings,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text, fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                _RoundButton(
                  icon: Icons.info_outline,
                  tooltip: s.about,
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Garad AI',
                    applicationVersion: '${s.version} ${app.appVersion}',
                    applicationLegalese: 'Powered by Arkaan AI Center.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // The signed-in account.
            _Card(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      _Avatar(name: user?.name ?? ''),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              user?.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _SectionLabel(s.account),
            _Card(
              children: [
                _Row(icon: Icons.person_outline, label: s.profile, onTap: soon),
                _Row(icon: Icons.attach_money, label: s.billing, onTap: soon),
                _Row(icon: Icons.notifications_none, label: s.notifications, onTap: soon),
                _Row(
                  icon: Icons.shield_outlined,
                  label: s.privacy,
                  onTap: _privacyUrl.isEmpty
                      ? soon
                      : () => launchUrl(Uri.parse(_privacyUrl), mode: LaunchMode.externalApplication),
                ),
              ],
            ),
            _SectionLabel(s.app),
            _Card(
              children: [
                _Row(
                  icon: Icons.schedule,
                  label: s.scheduled,
                  onTap: () {
                    Navigator.pop(context);
                    onOpenScheduled();
                  },
                ),
                _Row(icon: Icons.graphic_eq, label: s.voice, onTap: soon),
              ],
            ),
            _SectionLabel(s.appearance),
            _Card(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      for (final (mode, label) in [
                        (ThemeMode.light, s.light),
                        (ThemeMode.dark, s.dark),
                        (ThemeMode.system, s.system),
                      ]) ...[
                        if (mode != ThemeMode.light) const SizedBox(width: 10),
                        Expanded(
                          child: _ThemeTile(
                            mode: mode,
                            label: label,
                            selected: app.themeMode == mode,
                            onTap: () => app.setThemeMode(mode),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _Card(
              children: [
                _Row(
                  icon: Icons.logout,
                  label: s.logout,
                  color: c.danger,
                  chevron: false,
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        content: Text(s.logoutConfirm),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.logout)),
                        ],
                      ),
                    );
                    if (ok != true || !context.mounted) return;
                    final auth = context.read<AuthState>();
                    Navigator.pop(context);
                    await auth.logout();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A round letter avatar (the name's first letter).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      // Garad brand purple, like the logo.
      decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A round letter avatar for other screens (the side menu's account button).
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.name, this.size = 36});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => _Avatar(name: name, size: size);
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 22, 10, 8),
    child: Text(text, style: TextStyle(color: Palette.of(context).muted, fontSize: 13.5)),
  );
}

/// A rounded card with thin dividers between its rows.
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
            if (i > 0) Divider(height: 1, indent: 52, endIndent: 16, color: c.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap, this.color, this.chevron = true});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 21, color: color ?? c.text),
            const SizedBox(width: 15),
            Expanded(
              child: Text(label, style: TextStyle(color: color ?? c.text, fontSize: 15.5)),
            ),
            if (chevron) Icon(Icons.chevron_right, size: 20, color: c.faint),
          ],
        ),
      ),
    );
  }
}

/// A small picture of the app in that theme: Light, Dark, or half-and-half for System.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.mode, required this.label, required this.selected, required this.onTap});

  final ThemeMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    const lightBg = Color(0xFFFAF9F5);
    const darkBg = Color(0xFF262624);

    Widget preview(Color bg, Color line) => Container(
      color: bg,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 34, height: 3, color: line),
          const SizedBox(height: 4),
          Container(width: 24, height: 3, color: line),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1.45,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? c.brand : c.line, width: selected ? 2 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: switch (mode) {
                ThemeMode.light => preview(lightBg, const Color(0xFF8A8A85)),
                ThemeMode.dark => preview(darkBg, const Color(0xFF9A9A95)),
                ThemeMode.system => Stack(
                  fit: StackFit.expand,
                  children: [
                    preview(lightBg, const Color(0xFF8A8A85)),
                    ClipPath(clipper: _DiagonalClipper(), child: preview(darkBg, const Color(0xFF9A9A95))),
                  ],
                ),
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: selected ? c.brand : c.text, fontSize: 13)),
        ],
      ),
    );
  }
}

/// The lower-right triangle (System: dark below the diagonal).
class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
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
