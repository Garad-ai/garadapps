import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../widgets/auth_background.dart';
import '../widgets/google_logo.dart';
import 'auth_sheet.dart';

String _t(String so, String en) => chatStrings.isSomali ? so : en;

const _black = Color(0xFF000000);
const _sheet = Color(0xFF1E1E1E);
const _buttonDark = Color(0xFF2A2A2A);
const _line = Color(0xFF3A3A3A);
const _muted = Color(0xFF9A9A9A);

/// The first screen: behind it the same picture as the website's sign-in (the admin's looping video,
/// or slides), the Garad logo, and the ways in — Google (and Apple on iPhones), email, or Skip (chat
/// as a guest; the advanced features ask to log in).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;

  /// The website's sign-in picture; null until it arrives (or when there is none).
  WelcomeVisual? _visual;

  @override
  void initState() {
    super.initState();
    _loadVisual();
  }

  Future<void> _loadVisual() async {
    final visual = await context.read<AuthState>().api.welcomeVisual();
    if (mounted && visual != null && !visual.isEmpty) setState(() => _visual = visual);
  }

  Future<void> _skip() async {
    setState(() => _busy = true);
    try {
      await context.read<AuthState>().continueAsGuest();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = _visual;
    return Scaffold(
      backgroundColor: _black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (visual != null) ...[
            AuthBackground(visual: visual),
            // Dark at the top (the logo) and the bottom (the buttons), the picture clear in between.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xD9000000),
                    Color(0xFA000000),
                  ],
                  stops: [0, 0.2, 0.42, 0.68, 1],
                ),
              ),
            ),
          ],
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  if (visual == null)
                    // No picture: the logo in the middle, as before.
                    const Expanded(child: Center(child: _Brand(size: 64)))
                  else ...[
                    const SizedBox(height: 14),
                    const _Brand(size: 34, inRow: true),
                    const Spacer(),
                    if (visual.review.isNotEmpty || visual.bottom != null) ...[
                      _PoweredBy(review: visual.review, logo: visual.bottom),
                      const SizedBox(height: 18),
                    ],
                  ],
                  const LoginChoices(),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _busy ? null : _skip,
                    style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(120, 44)),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_t('Ka gudub', 'Skip'), style: const TextStyle(fontSize: 15)),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Garad logo and name: big in the middle, or small in a row at the top over the picture.
class _Brand extends StatelessWidget {
  const _Brand({required this.size, this.inRow = false});

  final double size;
  final bool inRow;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset('assets/images/splash-icon.png', height: size, semanticLabel: 'Garad AI');
    final name = Text(
      'Garad AI',
      style: TextStyle(color: Colors.white, fontSize: inRow ? 22 : 28, fontWeight: FontWeight.w600),
    );
    return inRow
        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [logo, const SizedBox(width: 10), name])
        : Column(mainAxisSize: MainAxisSize.min, children: [logo, const SizedBox(height: 18), name]);
  }
}

/// "GARAD AI Powered BY" and Arkaan's logo, as under the website's sign-in picture.
class _PoweredBy extends StatelessWidget {
  const _PoweredBy({required this.review, this.logo});

  final String review;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    final words = review.replaceAll(RegExp(r'[\s,]+$'), '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (words.isNotEmpty)
          Text(
            words.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2),
          ),
        if (logo != null) ...[
          const SizedBox(height: 6),
          Image.network(logo!, height: 40, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ],
      ],
    );
  }
}

/// A guest tapped something that needs an account (files, Garad Live…): ChatGPT's
/// "Log in to try advanced features" sheet.
Future<void> showLoginSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: _sheet,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                style: IconButton.styleFrom(backgroundColor: _buttonDark, foregroundColor: Colors.white),
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
            Text(
              _t('Gal si aad u isticmaasho awoodaha sare', 'Log in to try advanced features'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Hel jawaabo caqli badan, soo dir sawirro iyo faylal, la hadal Garad Live iyo wax kale markaad gasho.',
                'Get smarter responses, upload files, talk with Garad Live and more by logging in.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 22),
            LoginChoices(fromSheet: sheetContext),
          ],
        ),
      ),
    ),
  );
}

/// Continue with Google · OR · (Continue with Apple, on iPhones) · Log in or sign up.
class LoginChoices extends StatefulWidget {
  const LoginChoices({super.key, this.fromSheet});

  /// Set when shown in [showLoginSheet]: the sheet closes before moving on.
  final BuildContext? fromSheet;

  /// Sign in with Apple only on Apple devices — Android and the web get Google. (Apple asks apps that
  /// offer Google sign-in on iPhones to offer Sign in with Apple too.)
  static bool get showApple =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  @override
  State<LoginChoices> createState() => _LoginChoicesState();
}

class _LoginChoicesState extends State<LoginChoices> {
  /// The Google account picker is open, or the server is checking the account.
  bool _google = false;

  void _closeSheet() {
    final sheet = widget.fromSheet;
    if (sheet != null && sheet.mounted) Navigator.of(sheet).pop();
  }

  void _soon() {
    final messenger = ScaffoldMessenger.of(context);
    _closeSheet();
    messenger.showSnackBar(SnackBar(content: Text(chatStrings.comingSoon)));
  }

  /// The phone's Google account picker, then signed in: the app moves on to the chat by itself.
  Future<void> _continueWithGoogle() async {
    if (_google) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _google = true);
    try {
      final signedIn = await context.read<AuthState>().signInWithGoogle();
      if (signedIn) _closeSheet();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _google = false);
    }
  }

  void _email() {
    // ChatGPT's "Log in or sign up" sheet (email + code), over this screen.
    final navigator = Navigator.of(context);
    _closeSheet();
    showAuthSheet(navigator.context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChoiceButton(
          onTap: _google ? null : _continueWithGoogle,
          background: _buttonDark,
          foreground: Colors.white,
          border: _line,
          icon: _google
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const GoogleLogo(size: 20),
          label: _t('Ku sii wad Google', 'Continue with Google'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('OR', style: TextStyle(color: _muted, fontSize: 11)),
        ),
        if (LoginChoices.showApple) ...[
          _ChoiceButton(
            onTap: _soon,
            background: Colors.white,
            foreground: Colors.black,
            icon: const Icon(Icons.apple, size: 22, color: Colors.black),
            label: _t('Ku sii wad Apple', 'Continue with Apple'),
          ),
          const SizedBox(height: 10),
        ],
        _ChoiceButton(
          onTap: _google ? null : _email,
          background: _black.withValues(alpha: 0),
          foreground: Colors.white,
          border: _line,
          label: _t('Gal ama is diiwaangeli', 'Log in or sign up'),
        ),
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.label,
    this.icon,
    this.border,
  });

  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final Color? border;
  final Widget? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border!)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 10)],
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
