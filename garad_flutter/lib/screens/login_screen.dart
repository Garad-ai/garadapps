import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/garad_api.dart';
import '../auth_state.dart';
import '../auth_strings.dart';
import '../theme.dart';

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
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _signUp = false;
  bool _remember = true;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _lastName, _phone, _country, _email, _password, _confirm]) {
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
        await auth.register(
          name: _name.text,
          surname: _lastName.text,
          phone: _phone.text,
          country: _country.text,
          email: _email.text,
          password: _password.text,
          passwordConfirmation: _confirm.text,
        );
      } else {
        await auth.login(_email.text, _password.text, remember: _remember);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode() => setState(() {
        _signUp = !_signUp;
        _error = null;
        _form.currentState?.reset();
      });

  void _soon() => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authStrings.comingSoon)));

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  String? _requiredText(String? v) => (v == null || v.trim().isEmpty) ? authStrings.required : null;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final s = authStrings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? c.surface : Colors.white;

    return Scaffold(
      backgroundColor: dark ? c.background : const Color(0xFFEDEDF0),
      body: SafeArea(
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
                        Text(_signUp ? s.signUp : s.signIn,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.text)),
                        const SizedBox(height: 18),
                        OutlinedButton(
                          onPressed: _soon,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            side: BorderSide(color: c.line),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            foregroundColor: c.text,
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Text('G',
                                style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w800, fontSize: 17)),
                            const SizedBox(width: 10),
                            Text(s.googleLogin, style: const TextStyle(fontSize: 13)),
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(children: [
                            Expanded(child: Divider(color: c.line)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(s.or, style: TextStyle(color: c.faint, fontSize: 11)),
                            ),
                            Expanded(child: Divider(color: c.line)),
                          ]),
                        ),
                        if (_signUp) ...[
                          _Field(
                            label: '${s.name} *',
                            hint: s.nameHint,
                            controller: _name,
                            autofill: AutofillHints.givenName,
                            validator: _requiredText,
                          ),
                          _Field(
                            label: '${s.lastName} *',
                            hint: s.lastNameHint,
                            controller: _lastName,
                            autofill: AutofillHints.familyName,
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
                          _Field(
                            label: '${s.country} *',
                            hint: s.countryHint,
                            controller: _country,
                            autofill: AutofillHints.countryName,
                            validator: _requiredText,
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
                            icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 18, color: c.faint),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                          onSubmitted: _signUp ? null : (_) => _submit(),
                          validator: (v) {
                            if (v == null || v.isEmpty) return s.required;
                            if (_signUp && v.length < 8) return s.passwordShort;
                            return null;
                          },
                        ),
                        if (_signUp)
                          _Field(
                            label: '${s.confirmPassword} *',
                            hint: s.confirmPasswordHint,
                            controller: _confirm,
                            obscure: !_showPassword,
                            autofill: AutofillHints.newPassword,
                            onSubmitted: (_) => _submit(),
                            validator: (v) => v != _password.text ? s.passwordsDiffer : null,
                          ),
                        if (!_signUp)
                          Row(children: [
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
                              onPressed: _soon,
                              style: TextButton.styleFrom(foregroundColor: c.brand, padding: EdgeInsets.zero),
                              child: Text(s.forgotPassword, style: const TextStyle(fontSize: 12)),
                            ),
                          ]),
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
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : Text(_signUp ? s.signUp : s.signIn,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                        const SizedBox(height: 14),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(_signUp ? s.haveAccount : s.noAccount, style: TextStyle(fontSize: 12, color: c.muted)),
                          TextButton(
                            onPressed: _busy ? null : _switchMode,
                            style: TextButton.styleFrom(foregroundColor: c.brand),
                            child: Text(_signUp ? s.signIn : s.signUp, style: const TextStyle(fontSize: 12)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.lock, size: 13, color: c.muted),
                          const SizedBox(width: 6),
                          Flexible(child: Text(s.dataSafe, style: TextStyle(fontSize: 11.5, color: c.muted))),
                        ]),
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
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    OutlineInputBorder border(Color color) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.text)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboard,
          obscureText: obscure,
          autocorrect: false,
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
      ]),
    );
  }
}
