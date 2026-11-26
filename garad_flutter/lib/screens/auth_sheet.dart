import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/garad_api.dart';
import '../auth_state.dart';
import '../auth_strings.dart';
import '../widgets/google_logo.dart';

const _sheet = Color(0xFF212121);
const _field = Color(0xFF4D4D4D);
const _muted = Color(0xFFB4B4B4);
const _faint = Color(0xFF8E8E8E);
const _round = Color(0xFF3A3A3A);
const _danger = Color(0xFFFF6B6B);
const _success = Color(0xFF4ADE80);

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Sign in / Sign up, like garad.ai (email and password; full name to sign up; "Forgot password?"
/// sends the website's reset link), in a dark card that slides up, with ✕ to close. Or Google.
Future<void> showAuthSheet(BuildContext context, {bool signUp = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => AuthSheet(signUp: signUp),
  );
}

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key, this.signUp = false});

  /// Open on Sign up instead of Sign in.
  final bool signUp;

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  late bool _signUp = widget.signUp;

  /// The "Forgot password" screen (its own email box and "Send link"), opened from Sign in.
  bool _forgot = false;
  bool _showPassword = false;
  bool _busy = false;
  bool _google = false;
  String? _error;

  /// The server's "link sent" answer, shown in green on the Forgot password screen.
  String? _sent;

  AuthStrings get s => authStrings;

  String get _emailValue => _email.text.trim().toLowerCase();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchMode() => setState(() {
    _signUp = !_signUp;
    _error = null;
  });

  /// Runs [work] with the button spinning; a server message is shown above the button.
  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sign in / Sign up → signed in; the app moves on to the chat by itself.
  Future<void> _submit() async {
    String? problem;
    if (_signUp && _name.text.trim().isEmpty) {
      problem = s.required;
    } else if (!_emailPattern.hasMatch(_emailValue)) {
      problem = s.invalidEmail;
    } else if (_password.text.isEmpty) {
      problem = s.required;
    } else if (_signUp && _password.text.length < 8) {
      problem = s.passwordShort;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    await _run(() async {
      final auth = context.read<AuthState>();
      if (_signUp) {
        await auth.register(fullName: _name.text, email: _emailValue, password: _password.text);
      } else {
        await auth.login(_emailValue, _password.text);
      }
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Sign in → "Forgot password?": its own screen (the email typed on Sign in is kept).
  void _openForgot(bool open) => setState(() {
    _forgot = open;
    _error = null;
    _sent = null;
  });

  /// Forgot password → "Send link": the website's email with a link to choose a new password (on
  /// garad.ai), exactly as the website's Forgot Password page.
  Future<void> _sendResetLink() async {
    if (!_emailPattern.hasMatch(_emailValue)) {
      setState(() {
        _error = _email.text.trim().isEmpty ? s.required : s.invalidEmail;
        _sent = null;
      });
      return;
    }
    setState(() => _sent = null);
    await _run(() async {
      final message = await context.read<AuthState>().api.forgotPassword(_emailValue);
      if (mounted) setState(() => _sent = message.isEmpty ? s.linkSent : message);
    });
  }

  Future<void> _continueWithGoogle() async {
    if (_google || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _google = true;
      _error = null;
    });
    try {
      final signedIn = await context.read<AuthState>().signInWithGoogle();
      if (signedIn && mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _google = false);
    }
  }

  static bool get _showApple =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Widget build(BuildContext context) {
    // The card stays put when the keyboard opens (it covers the empty lower part); the form can still
    // scroll above the keyboard on small phones.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Material(
            color: _sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: double.infinity,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + keyboard),
                    child: AutofillGroup(child: _forgot ? _forgotForm() : _form()),
                  ),
                  if (_forgot)
                    Positioned(
                      left: 14,
                      top: 14,
                      child: _RoundButton(
                        icon: Icons.chevron_left,
                        label: s.back,
                        onTap: _busy ? null : () => _openForgot(false),
                      ),
                    ),
                  Positioned(
                    right: 14,
                    top: 14,
                    child: _RoundButton(
                      icon: Icons.close,
                      label: MaterialLocalizations.of(context).closeButtonTooltip,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Forgot password: like the website's page — an email box and "Send link"; the email opens
  /// garad.ai's page to choose a new password.
  Widget _forgotForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Image.asset('assets/images/splash-icon.png', height: 34, semanticLabel: 'Garad AI'),
        const SizedBox(height: 14),
        Text(
          s.forgotTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            s.forgotSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 15, height: 1.35),
          ),
        ),
        const SizedBox(height: 22),
        _Input(
          controller: _email,
          label: s.email,
          keyboard: TextInputType.emailAddress,
          autofill: AutofillHints.email,
          onSubmitted: (_) => _sendResetLink(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(_error!, style: const TextStyle(color: _danger, fontSize: 13)),
          ),
        if (_sent != null)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: _success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_sent!, style: const TextStyle(color: _success, fontSize: 14, height: 1.35)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _PrimaryButton(label: _sent == null ? s.sendLink : s.sendAgain, busy: _busy, onTap: _sendResetLink),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => _openForgot(false),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: Text(s.backToSignIn, style: const TextStyle(fontSize: 15)),
        ),
      ],
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Image.asset('assets/images/splash-icon.png', height: 34, semanticLabel: 'Garad AI'),
        const SizedBox(height: 14),
        Text(
          _signUp ? s.signUp : s.signIn,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            s.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 15, height: 1.35),
          ),
        ),
        const SizedBox(height: 22),
        if (_signUp) ...[
          _Input(
            controller: _name,
            label: s.fullName,
            keyboard: TextInputType.name,
            autofill: AutofillHints.name,
            capitalize: true,
          ),
          const SizedBox(height: 12),
        ],
        _Input(controller: _email, label: s.email, keyboard: TextInputType.emailAddress, autofill: AutofillHints.email),
        const SizedBox(height: 12),
        _Input(
          controller: _password,
          label: s.password,
          obscure: !_showPassword,
          autofill: _signUp ? AutofillHints.newPassword : AutofillHints.password,
          onSubmitted: (_) => _submit(),
          suffix: IconButton(
            tooltip: _showPassword ? s.hidePassword : s.showPassword,
            icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _faint),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        if (!_signUp)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _busy || _google ? null : () => _openForgot(true),
              style: TextButton.styleFrom(
                foregroundColor: _muted,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                minimumSize: Size.zero,
              ),
              child: Text(s.forgotPassword, style: const TextStyle(fontSize: 14)),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(_error!, style: const TextStyle(color: _danger, fontSize: 13)),
          ),
        const SizedBox(height: 14),
        _PrimaryButton(label: _signUp ? s.signUp : s.signIn, busy: _busy, onTap: _google ? null : _submit),
        _OrLine(text: s.or),
        _OutlineButton(
          label: s.google,
          icon: _google
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const GoogleLogo(size: 18),
          onTap: _busy || _google ? null : _continueWithGoogle,
        ),
        if (_showApple) ...[
          const SizedBox(height: 10),
          _OutlineButton(
            label: s.apple,
            icon: const Icon(Icons.apple, size: 20, color: Colors.white),
            filled: true,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.comingSoon))),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(_signUp ? s.haveAccount : s.noAccount, style: const TextStyle(color: _muted, fontSize: 14)),
            ),
            TextButton(
              onPressed: _busy || _google ? null : _switchMode,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(_signUp ? s.signIn : s.signUp, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.label,
    this.keyboard,
    this.autofill,
    this.capitalize = false,
    this.obscure = false,
    this.suffix,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboard;
  final String? autofill;
  final bool capitalize;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
      autofillHints: autofill == null ? null : [autofill!],
      textInputAction: onSubmitted == null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: onSubmitted,
      cursorColor: Colors.white,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _faint, fontSize: 15),
        floatingLabelStyle: const TextStyle(color: _muted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        suffixIcon: suffix,
        enabledBorder: border(_field),
        focusedBorder: border(Colors.white, 1.4),
        border: border(_field),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.75),
          shape: const StadiumBorder(),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
              )
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.icon, required this.onTap, this.filled = false});

  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  /// Black filled (Apple), instead of an outline.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: filled ? Colors.black : Colors.transparent,
          side: BorderSide(color: filled ? Colors.black : _field),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _OrLine extends StatelessWidget {
  const _OrLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: _round, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(text, style: const TextStyle(color: _faint, fontSize: 12)),
          ),
          const Expanded(child: Divider(color: _round, height: 1)),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      style: IconButton.styleFrom(
        backgroundColor: _round,
        foregroundColor: Colors.white,
        fixedSize: const Size(40, 40),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}
