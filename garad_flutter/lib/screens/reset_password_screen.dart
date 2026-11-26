import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/garad_api.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../theme.dart';

/// The code in a password reset link from the email (https://garad.ai/forgot-password/retrieve/{code}),
/// or null when [uri] is some other link. Android opens these links in the app (App Links).
String? passwordResetCode(Uri uri) {
  if (uri.scheme != 'https' || (uri.host != 'garad.ai' && uri.host != 'www.garad.ai')) return null;
  final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  if (parts.length != 3 || parts[0] != 'forgot-password' || parts[1] != 'retrieve') return null;
  return parts[2].isEmpty ? null : parts[2];
}

/// "Choose a new password", opened by the reset link in the email. Saving it signs this phone in
/// (the same as the website's Change Password page), and the chat opens.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.code});

  final String code;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  /// The link is used or older than an hour: only "request a new link" helps.
  bool _expired = false;

  static String _t(String so, String en) => chatStrings.isSomali ? so : en;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _password.text;
    if (password.length < 8) {
      setState(() => _error = _t('Furaha sirta ah: ugu yaraan 8 xaraf.', 'Your password needs at least 8 characters.'));
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = _t('Labada furaha isma laha.', "The two passwords don't match."));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().resetPassword(code: widget.code, password: password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Furahaaga cusub waa la keydiyay.', 'Your new password is saved.'))),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        _expired = e.statusCode == 410;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
    InputDecoration decoration(String label) => InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: border(c.line),
      focusedBorder: border(c.brand, 1.4),
      border: border(c.line),
      suffixIcon: IconButton(
        tooltip: _show ? _t('Qari', 'Hide password') : _t('Muuji', 'Show password'),
        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: c.muted),
        onPressed: () => setState(() => _show = !_show),
      ),
    );

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, elevation: 0, scrolledUnderElevation: 0),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              _t('Dooro furaha cusub', 'Choose a new password'),
              style: TextStyle(color: c.text, fontSize: 26, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Kadib waxaad si toos ah u gali doontaa akoonkaaga.',
                "You'll be signed in to your account straight after.",
              ),
              style: TextStyle(color: c.muted, fontSize: 15),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _password,
              enabled: !_busy && !_expired,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              onChanged: (_) => _error == null ? null : setState(() => _error = null),
              decoration: decoration(_t('Furaha cusub', 'New password')),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _confirm,
              enabled: !_busy && !_expired,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onChanged: (_) => _error == null ? null : setState(() => _error = null),
              onSubmitted: (_) => _save(),
              decoration: decoration(_t('Ku celi furaha', 'Confirm new password')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: c.danger, fontSize: 14)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                // An expired link: back to the sign-in screen, where "Forgot password?" sends a new one.
                onPressed: _busy ? null : (_expired ? () => Navigator.of(context).pop() : _save),
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: c.brandSoft,
                  shape: const StadiumBorder(),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(
                        _expired
                            ? _t('Codso link cusub', 'Request a new link')
                            : _t('Keydi furaha', 'Save password'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
