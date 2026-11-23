import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/garad_api.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import 'login_screen.dart';

String _t(String so, String en) => chatStrings.isSomali ? so : en;

const _black = Color(0xFF000000);
const _sheet = Color(0xFF1E1E1E);
const _buttonDark = Color(0xFF2A2A2A);
const _line = Color(0xFF3A3A3A);
const _muted = Color(0xFF9A9A9A);

/// The first screen, like ChatGPT: the Garad logo and the ways in — Google, Apple, email, or Skip
/// (chat as a guest; the advanced features ask to log in).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;

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
    return Scaffold(
      backgroundColor: _black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/splash-icon.png', height: 64, semanticLabel: 'Garad AI'),
                    const SizedBox(height: 18),
                    const Text(
                      'Garad AI',
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
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
              const SizedBox(height: 10),
              Text(
                _t(
                  'Garad AI waa AI. Markaad isticmaashid, waxaad oggolaatay Shuruudaha iyo Siyaasadda Xogta.',
                  'Garad AI is AI. By using it, you agree to our Terms & Privacy Policy.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
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

/// Continue with Google · OR · Continue with Apple · Log in or sign up.
class LoginChoices extends StatelessWidget {
  const LoginChoices({super.key, this.fromSheet});

  /// Set when shown in [showLoginSheet]: the sheet closes before moving on.
  final BuildContext? fromSheet;

  void _closeSheet() {
    final sheet = fromSheet;
    if (sheet != null && sheet.mounted) Navigator.of(sheet).pop();
  }

  void _soon(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    _closeSheet();
    messenger.showSnackBar(SnackBar(content: Text(chatStrings.comingSoon)));
  }

  void _email(BuildContext context) {
    final navigator = Navigator.of(context);
    _closeSheet();
    navigator.push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChoiceButton(
          onTap: () => _soon(context),
          background: _buttonDark,
          foreground: Colors.white,
          border: _line,
          icon: const Text(
            'G',
            style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w800, fontSize: 18),
          ),
          label: _t('Ku sii wad Google', 'Continue with Google'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('OR', style: TextStyle(color: _muted, fontSize: 11)),
        ),
        _ChoiceButton(
          onTap: () => _soon(context),
          background: Colors.white,
          foreground: Colors.black,
          icon: const Icon(Icons.apple, size: 22, color: Colors.black),
          label: _t('Ku sii wad Apple', 'Continue with Apple'),
        ),
        const SizedBox(height: 10),
        _ChoiceButton(
          onTap: () => _email(context),
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

  final VoidCallback onTap;
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
