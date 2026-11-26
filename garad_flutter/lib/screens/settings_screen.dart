import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';
import 'billing_screen.dart';
import 'settings_pages.dart';

/// Settings, ChatGPT/Claude-style: ✕ · "Settings" · ⓘ, the account card (opens Profile),
/// Account / App rows, Appearance (Light / Dark / System) and Log out.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.onOpenScheduled, this.onChatsDeleted});

  final VoidCallback onOpenScheduled;

  /// Privacy → Delete all chats: the chat screen starts a new chat.
  final VoidCallback? onChatsDeleted;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = chatStrings;
    final user = context.watch<AuthState>().user;
    final app = context.watch<AppState>();

    void open(Widget page) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

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
                // Keeps the title centred (same width as the ✕ button).
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 20),
            // The signed-in account.
            _Card(
              children: [
                InkWell(
                  onTap: () => open(const ProfileScreen()),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        _Avatar(name: user?.fullName ?? ''),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.fullName ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                              // The plan, like ChatGPT ("Free", "Professional"); the email is in Profile.
                              const _PlanLabel(),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 20, color: c.faint),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            _SectionLabel(s.account),
            _Card(
              children: [
                _Row(icon: Icons.person_outline, label: s.profile, onTap: () => open(const ProfileScreen())),
                _Row(icon: Icons.attach_money, label: s.billing, onTap: () => open(const BillingScreen())),
                _Row(
                  icon: Icons.notifications_none,
                  label: s.notifications,
                  onTap: () => open(const NotificationsScreen()),
                ),
                _Row(
                  icon: Icons.shield_outlined,
                  label: s.privacy,
                  onTap: () => open(PrivacyScreen(onChatsDeleted: onChatsDeleted)),
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
                _Row(icon: Icons.graphic_eq, label: s.voice, onTap: () => open(const VoiceSettingsScreen())),
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
                      barrierColor: Colors.black.withValues(alpha: 0.45),
                      builder: (_) => const _SignOutDialog(),
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

/// "Sign out?" — clean, in the app's colours: the question, a Garad-purple Sign out and Cancel.
class _SignOutDialog extends StatelessWidget {
  const _SignOutDialog();

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = chatStrings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: dark ? c.surfaceStrong : Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.logoutConfirm,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                child: Text(s.logout, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.text,
                  side: BorderSide(color: c.line),
                  shape: const StadiumBorder(),
                ),
                child: Text(s.cancel, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Free" or the plan's name under the account's name (shown at once from the last check, then refreshed).
class _PlanLabel extends StatefulWidget {
  const _PlanLabel();

  @override
  State<_PlanLabel> createState() => _PlanLabelState();
}

class _PlanLabelState extends State<_PlanLabel> {
  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthState>();
    if (auth.user?.guest ?? true) return;
    auth.api.billing().then((_) {
      if (mounted) setState(() {});
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final status = context.read<AuthState>().api.cachedBilling;
    final plan = status == null ? '' : (status.planName ?? (chatStrings.isSomali ? 'Bilaash' : 'Free'));
    return Text(
      plan,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: Palette.of(context).muted, fontSize: 13),
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
