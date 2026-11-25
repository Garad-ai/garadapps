import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../auth_state.dart';
import '../auth_strings.dart';
import '../chat_strings.dart';
import '../theme.dart';
import '../widgets/auth_background.dart';

/// Links shown under the form. Set at build time, e.g.
///   --dart-define=TERMS_URL=https://garad.ai/terms --dart-define=PRIVACY_URL=https://garad.ai/privacy
/// Without them the words are shown as plain text.
const String _termsUrl = String.fromEnvironment('TERMS_URL');
const String _privacyUrl = String.fromEnvironment('PRIVACY_URL');

/// The violet of the Sign in / Sign up button in the Garad web design.
const Color _buttonViolet = Color(0xFF7B1FF2);

/// Sign in, or switch to Sign up.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _signUp = false;
  bool _remember = true;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  /// The website's sign-in video (or slides) behind the form, as on the welcome screen.
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

  @override
  void dispose() {
    for (final c in [_fullName, _phone, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    try {
      if (_signUp) {
        await auth.register(fullName: _fullName.text, phone: _phone.text, email: _email.text, password: _password.text);
      } else {
        await auth.login(_email.text, _password.text, remember: _remember);
      }
      _closeIfPushed();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opened from the welcome screen or the guest chat: back to the (now signed-in) chat.
  void _closeIfPushed() {
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _switchMode() => setState(() {
    _signUp = !_signUp;
    _error = null;
    _form.currentState?.reset();
  });

  /// "Forgot password?": asks for the email (the one typed above, if any) and sends a reset link.
  Future<void> _forgotPassword() async {
    FocusScope.of(context).unfocus();
    final somali = chatStrings.isSomali;
    String t(String so, String en) => somali ? so : en;
    final email = TextEditingController(text: _email.text.trim());
    final api = context.read<AuthState>().api;
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var sending = false;
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialog) {
            Future<void> send() async {
              final value = email.text.trim();
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                setDialog(() => error = authStrings.invalidEmail);
                return;
              }
              setDialog(() {
                sending = true;
                error = null;
              });
              try {
                final message = await api.forgotPassword(value);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(message);
              } on ApiException catch (e) {
                setDialog(() {
                  sending = false;
                  error = e.message;
                });
              }
            }

            return AlertDialog(
              title: Text(t('Dib u dhig furaha', 'Reset your password')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t(
                      'Geli email-kaaga. Waxaan kuu soo diraynaa link aad ku beddesho furaha.',
                      'Enter your email. We will send you a link to choose a new password.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    autofocus: email.text.isEmpty,
                    onSubmitted: (_) => sending ? null : send(),
                    decoration: InputDecoration(hintText: authStrings.emailHint, errorText: error),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(t('Jooji', 'Cancel')),
                ),
                FilledButton(
                  onPressed: sending ? null : send,
                  child: sending
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t('Dir link-ga', 'Send link')),
                ),
              ],
            );
          },
        );
      },
    );
    if (sent != null && sent.isNotEmpty) messenger.showSnackBar(SnackBar(content: Text(sent)));
  }

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  String? _requiredText(String? v) => (v == null || v.trim().isEmpty) ? authStrings.required : null;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = authStrings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? c.surface : Colors.white;
    final visual = _visual;

    return Scaffold(
      backgroundColor: visual != null ? Colors.black : (dark ? c.background : const Color(0xFFEDEDF0)),
      extendBodyBehindAppBar: visual != null,
      // Opened from the welcome screen or the guest chat: a way back.
      appBar: Navigator.of(context).canPop()
          ? AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              foregroundColor: visual != null ? Colors.white : c.text,
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The website's sign-in video behind the card, darkened so the card stands out.
          if (visual != null) ...[AuthBackground(visual: visual), const ColoredBox(color: Color(0x73000000))],
          _card(c, s, card),
        ],
      ),
    );
  }

  /// The white Sign in / Sign up card, centred and scrolling above the keyboard.
  Widget _card(Palette c, AuthStrings s, Color card) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20)),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Image.asset('assets/images/splash-icon.png', height: 30, semanticLabel: 'Garad AI'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _signUp ? s.signUp : s.signIn,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.text),
                      ),
                      // Google and Skip are on the welcome screen, so this page is the email form alone.
                      const SizedBox(height: 18),
                      if (_signUp) ...[
                        _Field(
                          label: '${s.fullName} *',
                          hint: s.fullNameHint,
                          controller: _fullName,
                          keyboard: TextInputType.name,
                          capitalize: true,
                          autofill: AutofillHints.name,
                          validator: _requiredText,
                        ),
                        _Field(
                          label: '${s.phone} *',
                          hint: s.phoneHint,
                          controller: _phone,
                          keyboard: TextInputType.phone,
                          autofill: AutofillHints.telephoneNumber,
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.isEmpty) return s.required;
                            return RegExp(r'^\+?[0-9 ()-]{6,32}$').hasMatch(value) ? null : s.invalidPhone;
                          },
                        ),
                      ],
                      _Field(
                        label: _signUp ? '${s.email} *' : s.email,
                        hint: s.emailHint,
                        controller: _email,
                        keyboard: TextInputType.emailAddress,
                        autofill: AutofillHints.email,
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return s.required;
                          return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value) ? null : s.invalidEmail;
                        },
                      ),
                      _Field(
                        label: _signUp ? '${s.password} *' : s.password,
                        hint: s.passwordHint,
                        controller: _password,
                        obscure: !_showPassword,
                        autofill: _signUp ? AutofillHints.newPassword : AutofillHints.password,
                        suffix: IconButton(
                          icon: Icon(
                            _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                            color: c.faint,
                          ),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                        onSubmitted: (_) => _submit(),
                        validator: (v) {
                          if (v == null || v.isEmpty) return s.required;
                          if (_signUp && v.length < 8) return s.passwordShort;
                          return null;
                        },
                      ),
                      if (!_signUp)
                        Row(
                          children: [
                            SizedBox.square(
                              dimension: 22,
                              child: Checkbox(
                                value: _remember,
                                activeColor: c.brand,
                                visualDensity: VisualDensity.compact,
                                onChanged: (v) => setState(() => _remember = v ?? true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(s.rememberMe, style: TextStyle(fontSize: 12, color: c.muted)),
                            const Spacer(),
                            TextButton(
                              onPressed: _busy ? null : _forgotPassword,
                              style: TextButton.styleFrom(foregroundColor: c.brand, padding: EdgeInsets.zero),
                              child: Text(s.forgotPassword, style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: _buttonViolet,
                          disabledBackgroundColor: _buttonViolet.withValues(alpha: 0.6),
                          minimumSize: const Size.fromHeight(50),
                          shape: const StadiumBorder(),
                        ),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(
                                _signUp ? s.signUp : s.signIn,
                                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_signUp ? s.haveAccount : s.noAccount, style: TextStyle(fontSize: 12, color: c.muted)),
                          TextButton(
                            onPressed: _busy ? null : _switchMode,
                            style: TextButton.styleFrom(foregroundColor: c.brand),
                            child: Text(_signUp ? s.signIn : s.signUp, style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock, size: 13, color: c.muted),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(s.dataSafe, style: TextStyle(fontSize: 11.5, color: c.muted)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 11.5, color: c.muted, height: 1.6),
                          children: [
                            TextSpan(text: '${s.agreePrefix} '),
                            _link(s.terms, _termsUrl, c),
                            TextSpan(text: '\n${s.readOur} '),
                            _link(s.privacy, _privacyUrl, c),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextSpan _link(String text, String url, Palette c) => TextSpan(
    text: text,
    style: TextStyle(color: c.text, decoration: TextDecoration.underline),
    recognizer: url.isEmpty ? null : (TapGestureRecognizer()..onTap = () => _open(url)),
  );
}

/// Label above a rounded text box, as in the web design.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.validator,
    this.keyboard,
    this.autofill,
    this.obscure = false,
    this.capitalize = false,
    this.suffix,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboard;
  final String? autofill;
  final bool obscure;

  /// Capital letter at the start of each word (names).
  final bool capitalize;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.text),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            validator: validator,
            keyboardType: keyboard,
            obscureText: obscure,
            autocorrect: false,
            textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
            autofillHints: autofill == null ? null : [autofill!],
            textInputAction: onSubmitted == null ? TextInputAction.next : TextInputAction.done,
            onFieldSubmitted: onSubmitted,
            style: TextStyle(fontSize: 14, color: c.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(color: c.faint, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              suffixIcon: suffix,
              enabledBorder: border(c.line),
              focusedBorder: border(c.brand),
              errorBorder: border(c.danger),
              focusedErrorBorder: border(c.danger),
            ),
          ),
        ],
      ),
    );
  }
}
