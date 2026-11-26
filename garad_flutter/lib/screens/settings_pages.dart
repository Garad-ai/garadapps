import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/garad_api.dart';
import '../api/models.dart';
import '../app_storage.dart';
import '../auth_state.dart';
import '../chat_strings.dart';
import '../notifications.dart';
import '../theme.dart';

String _t(String so, String en) => chatStrings.isSomali ? so : en;

/// Set at build time to use another privacy page than the website's (`--dart-define=PRIVACY_URL=…`).
const String _privacyUrlSetting = String.fromEnvironment('PRIVACY_URL');

/// The phone's saved choice of Garad's voice for calls (shared with the chat screen's calls).
const String callVoiceKey = 'garad_call_voice';

// ============================================================================================
// Profile: name, phone, email, password and account deletion, with the website's own rules.
// ============================================================================================

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final auth = context.watch<AuthState>();
    final user = auth.user;
    String date(DateTime d) => '${d.day}/${d.month}/${d.year}';

    if (user == null || user.guest) {
      return SettingsPage(
        title: _t('Profile', 'Profile'),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text(
              _t('Gal akoonkaaga si aad u aragto profile-kaaga.', 'Sign in to see your profile.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 15),
            ),
          ),
        ],
      );
    }

    Future<void> editName() => showFormSheet(
      context,
      title: _t('Magacaaga', 'Your name'),
      fields: [
        FieldSpec(label: _t('Magaca oo buuxa', 'Full name'), initial: user.fullName, autofill: AutofillHints.name),
      ],
      action: _t('Kaydi', 'Save'),
      submit: (values) async {
        if (values[0].trim().isEmpty) return _t('Geli magacaaga.', 'Enter your name.');
        await auth.updateProfile(fullName: values[0], phone: user.phone);
        return null;
      },
    );

    Future<void> editPhone() => showFormSheet(
      context,
      title: _t('Taleefanka', 'Phone number'),
      subtitle: _t('Ka tag madhan si aad u tirtirto.', 'Leave it empty to remove it.'),
      fields: [
        FieldSpec(
          label: _t('Lambarka taleefanka', 'Phone number'),
          initial: user.phone,
          hint: '+252 61 234 5678',
          keyboard: TextInputType.phone,
          autofill: AutofillHints.telephoneNumber,
          allow: RegExp(r'[0-9 +]'),
        ),
      ],
      action: _t('Kaydi', 'Save'),
      submit: (values) async {
        final phone = values[0].trim();
        if (phone.isNotEmpty && !RegExp(r'^\+?[0-9 ]{6,}$').hasMatch(phone)) {
          return _t('Geli lambar sax ah.', 'Enter a valid phone number.');
        }
        await auth.updateProfile(fullName: user.fullName, phone: phone);
        return null;
      },
    );

    Future<void> changePassword() async {
      final messenger = ScaffoldMessenger.of(context);
      String? done;
      final ok = await showFormSheet(
        context,
        title: user.google ? _t('Samee furaha sirta', 'Set a password') : _t('Beddel furaha sirta', 'Change password'),
        subtitle: user.google
            ? _t(
                'Akoonkaaga waxaa lagu sameeyay Google. Furaha sirta ah wuxuu kuu oggolaanayaa inaad ku gasho email-kaaga. '
                    'Marka aad kaydiso, Google ayaad ku xaqiijin doontaa inay tahay adiga.',
                'Your account was made with Google. A password also lets you sign in with your email. '
                    'When you save, confirm with Google that it’s you.',
              )
            : null,
        fields: [
          if (!user.google)
            FieldSpec(label: _t('Furaha hadda', 'Current password'), obscure: true, autofill: AutofillHints.password),
          FieldSpec(
            label: _t('Furaha cusub', 'New password'),
            obscure: true,
            autofill: AutofillHints.newPassword,
            hint: _t('Ugu yaraan 8 xaraf', 'At least 8 characters'),
          ),
        ],
        action: _t('Kaydi', 'Save'),
        submit: (values) async {
          final current = user.google ? '' : values[0];
          final next = values.last;
          if (!user.google && current.isEmpty) return _t('Geli furahaaga hadda.', 'Enter your current password.');
          if (next.length < 8) return _t('Furaha cusub: ugu yaraan 8 xaraf.', 'New password: at least 8 characters.');
          // A Google account has no password to type: a fresh Google sign-in proves it's the owner.
          String? googleIdToken;
          if (user.google) {
            googleIdToken = await auth.confirmWithGoogle();
            if (googleIdToken == null) return _t('Ku xaqiiji Google si aad u sii wadato.', 'Confirm with Google to continue.');
          }
          done = await auth.api.changePassword(current: current, password: next, googleIdToken: googleIdToken);
          return null;
        },
      );
      if (ok) messenger.showSnackBar(SnackBar(content: Text(done ?? _t('Waa la beddelay.', 'Password changed.'))));
    }

    Future<void> deleteAccount() async {
      String? done;
      final ok = await showFormSheet(
        context,
        title: _t('Tirtir akoonka', 'Delete account'),
        subtitle: _t(
          'Codsigaaga waxaa eegaya kooxda Garad, kadibna akoonkaaga, wada-hadalladaada iyo xogtaada waa la tirtirayaa. '
              'Tan dib looma soo celin karo.',
          'The Garad team reviews your request, then deletes your account, chats and data. This can’t be undone.',
        ),
        fields: [
          user.google
              ? FieldSpec(
                  label: _t('Qor email-kaaga si aad u xaqiijiso', 'Type your email to confirm'),
                  hint: user.email,
                  keyboard: TextInputType.emailAddress,
                )
              : FieldSpec(
                  label: _t('Furahaaga sirta', 'Your password'),
                  obscure: true,
                  autofill: AutofillHints.password,
                ),
        ],
        action: _t('Codso tirtirid', 'Request deletion'),
        danger: true,
        submit: (values) async {
          if (values[0].trim().isEmpty) return _t('Waa loo baahan yahay.', 'Required.');
          if (!user.google) {
            done = await auth.api.requestAccountDeletion(password: values[0]);
            return null;
          }
          // A Google account: the typed email is the "are you sure", then a fresh Google sign-in
          // proves it's the owner (a saved login on a lost phone is not enough).
          if (values[0].trim().toLowerCase() != user.email.toLowerCase()) {
            return _t('Qor email-kaaga si sax ah.', 'Type your email exactly to confirm.');
          }
          final googleIdToken = await auth.confirmWithGoogle();
          if (googleIdToken == null) return _t('Ku xaqiiji Google si aad u sii wadato.', 'Confirm with Google to continue.');
          done = await auth.api.requestAccountDeletion(googleIdToken: googleIdToken);
          return null;
        },
      );
      if (ok && context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            content: Text(done ?? _t('Codsigaaga waa la diray.', 'Your request has been sent.')),
            actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('OK'))],
          ),
        );
      }
    }

    return SettingsPage(
      title: _t('Profile', 'Profile'),
      children: [
        const SizedBox(height: 8),
        Center(child: LetterAvatar(name: user.fullName, size: 76)),
        const SizedBox(height: 12),
        Text(
          user.fullName,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text, fontSize: 21, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          user.email,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 14),
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.person_outline,
              label: _t('Magaca', 'Name'),
              value: user.fullName,
              onTap: editName,
            ),
            SettingsTile(
              icon: Icons.phone_outlined,
              label: _t('Taleefanka', 'Phone'),
              value: user.phone.isEmpty ? _t('Ku dar', 'Add') : user.phone,
              onTap: editPhone,
            ),
            SettingsTile(icon: Icons.mail_outline, label: _t('Email', 'Email'), value: user.email),
            if (user.createdAt case final since?)
              SettingsTile(
                icon: Icons.calendar_today_outlined,
                label: _t('Xubin tan iyo', 'Member since'),
                value: date(since),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.lock_outline,
              label: user.google
                  ? _t('Samee furaha sirta', 'Set a password')
                  : _t('Beddel furaha sirta', 'Change password'),
              onTap: changePassword,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.delete_outline,
              label: _t('Tirtir akoonka', 'Delete account'),
              color: c.danger,
              chevron: false,
              onTap: deleteAccount,
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================================
// Voice: the voice Garad speaks with in calls, with a sample of each.
// ============================================================================================

class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final _player = AudioPlayer();
  List<AiVoice>? _voices;
  String? _selected;
  String? _loading;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthState>().api;
    String? saved;
    try {
      saved = await const AppStorage().read(key: callVoiceKey);
    } catch (_) {}
    try {
      final voices = await api.voices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        // What calls use: the saved choice, or the first voice.
        _selected = (voices.where((v) => v.id == saved).firstOrNull ?? voices.firstOrNull)?.id;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Picks the voice for calls and says hello in it.
  Future<void> _choose(AiVoice voice) async {
    setState(() {
      _selected = voice.id;
      _loading = voice.id;
    });
    unawaited(const AppStorage().write(key: callVoiceKey, value: voice.id).catchError((_) {}));
    final api = context.read<AuthState>().api;
    try {
      await _player.stop();
      final bytes = await api.speech(
        voice.id,
        _t('Salaan, waxaan ahay ${voice.name}. Aan wada hadalno.', "Hi, I'm ${voice.name}. Let's talk."),
      );
      if (!mounted || _selected != voice.id) return;
      await _player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // No sound on this device: the choice is still saved.
    } finally {
      if (mounted && _loading == voice.id) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final voices = _voices;
    return SettingsPage(
      title: _t('Codka', 'Voice'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
          child: Text(
            _t(
              'Codka Garad ku hadlo wicitaannada codka iyo muuqaalka. Taabo cod si aad u maqasho. '
                  'Codadka AI-ga waxaa sameeyay AI — ma aha dad dhab ah.',
              'The voice Garad speaks with in voice and video calls. Tap one to hear it. '
                  'AI voices are AI-generated, not real people.',
            ),
            style: TextStyle(color: c.muted, fontSize: 14, height: 1.4),
          ),
        ),
        if (_error != null)
          Center(
            child: Column(
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
                TextButton(onPressed: _load, child: Text(_t('Isku day mar kale', 'Try again'))),
              ],
            ),
          )
        else if (voices == null)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (voices.isEmpty)
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.smartphone,
                label: _t('Codka taleefanka', 'Phone voice'),
                value: _t('Bilaash · internet la’aan', 'Free · works offline'),
                trailing: Icon(Icons.check_circle, color: c.brand),
              ),
            ],
          )
        else
          SettingsGroup(
            children: [
              for (final v in voices)
                SettingsTile(
                  icon: Icons.graphic_eq,
                  label: v.name,
                  subtitle: v.description,
                  onTap: () => _choose(v),
                  trailing: _loading == v.id
                      ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.brand))
                      : _selected == v.id
                      ? Icon(Icons.check_circle, color: c.brand)
                      : Icon(Icons.play_circle_outline, color: c.faint),
                ),
            ],
          ),
      ],
    );
  }
}

// ============================================================================================
// Notifications: "Responses", like ChatGPT.
// ============================================================================================

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Whether the phone lets Garad show notifications (null while checking).
  bool? _allowed;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _check();
    // Back from the phone's settings: check again.
    _lifecycle = AppLifecycleListener(onResume: _check);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final allowed = await GaradNotifications.allowedByPhone();
    if (mounted) setState(() => _allowed = allowed);
  }

  Future<void> _toggle(bool on) async {
    await GaradNotifications.setResponses(on);
    if (on && _allowed != true) {
      final allowed = await GaradNotifications.askPhone();
      if (mounted) setState(() => _allowed = allowed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    if (!GaradNotifications.supported) {
      return SettingsPage(
        title: _t('Ogeysiisyada', 'Notifications'),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text(
              _t('Ogeysiisyadu waxay ku jiraan app-ka Android.', 'Notifications are in the Android app.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 15),
            ),
          ),
        ],
      );
    }
    return SettingsPage(
      title: _t('Ogeysiisyada', 'Notifications'),
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: GaradNotifications.responses,
          builder: (context, on, _) => SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.chat_bubble_outline,
                label: _t('Jawaabaha', 'Responses'),
                subtitle: _t(
                  'La socodsii marka Garad dhammeeyo jawaab adigoo app kale ku jira.',
                  'Get notified when Garad finishes an answer while you’re in another app.',
                ),
                onTap: () => _toggle(!on),
                trailing: Switch(
                  value: on,
                  activeThumbColor: Colors.white,
                  activeTrackColor: c.brand,
                  onChanged: _toggle,
                ),
              ),
            ],
          ),
        ),
        if (_allowed == false && GaradNotifications.responses.value) ...[
          const SizedBox(height: 16),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.notifications_off_outlined,
                label: _t('Taleefanku wuu xannibay', 'Blocked on this phone'),
                subtitle: _t(
                  'U oggolow Garad AI ogeysiisyada dejinta taleefanka.',
                  'Allow notifications for Garad AI in your phone’s settings.',
                ),
                color: c.danger,
                onTap: () async {
                  if (!await GaradNotifications.askPhone()) await openAppSettings();
                  await _check();
                },
                trailing: Text(
                  _t('Fur', 'Open'),
                  style: TextStyle(color: c.brand, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ============================================================================================
// Privacy (ChatGPT's Data controls): the website's policy and terms, and deleting all chats.
// ============================================================================================

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, this.onChatsDeleted});

  /// Called after "Delete all chats", so the open chat is cleared too.
  final VoidCallback? onChatsDeleted;

  /// A page of the website the app talks to (garad.ai, or the local copy while testing).
  static String websitePage(String path) => '${apiBaseUrl.replaceFirst(RegExp(r'/api/mobile$'), '')}$path';

  static Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView).catchError((_) => false);

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final privacyUrl = _privacyUrlSetting.isNotEmpty ? _privacyUrlSetting : websitePage('/privacy-policy');

    Future<void> deleteAll() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(_t('Tirtir dhammaan wada-hadallada?', 'Delete all chats?')),
          content: Text(
            _t(
              'Dhammaan wada-hadalladaada waa laga tirtirayaa app-ka iyo garad.ai. Tan dib looma soo celin karo.',
              'All your chats will be deleted from the app and garad.ai. This can’t be undone.',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(chatStrings.cancel)),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              style: FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white),
              child: Text(_t('Tirtir', 'Delete')),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await context.read<AuthState>().api.deleteAllConversations();
        onChatsDeleted?.call();
        messenger.showSnackBar(SnackBar(content: Text(_t('Dhammaan waa la tirtiray.', 'All chats deleted.'))));
      } on ApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    return SettingsPage(
      title: _t('Asturnaanta', 'Privacy'),
      children: [
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.shield_outlined,
              label: _t('Siyaasadda asturnaanta', 'Privacy policy'),
              trailingIcon: Icons.open_in_new,
              onTap: () => _open(privacyUrl),
            ),
            SettingsTile(
              icon: Icons.description_outlined,
              label: _t('Shuruudaha isticmaalka', 'Terms of use'),
              trailingIcon: Icons.open_in_new,
              onTap: () => _open(websitePage('/terms')),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.delete_sweep_outlined,
              label: _t('Tirtir dhammaan wada-hadallada', 'Delete all chats'),
              color: c.danger,
              chevron: false,
              onTap: deleteAll,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: Text(
            _t(
              'Wada-hadalladaadu waxay ku kaydsan yihiin akoonkaaga Garad, sidaa darteed waxaad ka arki kartaa garad.ai sidoo kale.',
              'Your chats are saved to your Garad account, so you also see them on garad.ai.',
            ),
            style: TextStyle(color: c.faint, fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}

// ============================================================================================
// Shared pieces: the page, a rounded group of rows, a row, the letter avatar and the form sheet.
// ============================================================================================

/// A settings page: ‹ back · centered title, then the content.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                Tooltip(
                  message: MaterialLocalizations.of(context).backButtonTooltip,
                  child: Material(
                    color: Colors.transparent,
                    shape: CircleBorder(side: BorderSide(color: c.line)),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(context),
                      child: SizedBox.square(dimension: 40, child: Icon(Icons.chevron_left, color: c.text)),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text, fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A rounded card with thin dividers between its rows (like Settings).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

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

/// A row: icon · label (and a line under it) · value · chevron (or [trailing]).
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.onTap,
    this.color,
    this.chevron = true,
    this.trailing,
    this.trailingIcon,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Color? color;
  final bool chevron;
  final Widget? trailing;
  final IconData? trailingIcon;

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
            // With a value: label on the left, the value pushed to the right edge (by the chevron).
            if (value != null) ...[
              Text(label, style: TextStyle(color: color ?? c.text, fontSize: 15.5)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(color: c.muted, fontSize: 14.5),
                ),
              ),
            ] else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: color ?? c.text, fontSize: 15.5)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
                    ],
                  ],
                ),
              ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ] else if (trailingIcon != null) ...[
              const SizedBox(width: 6),
              Icon(trailingIcon, size: 18, color: c.faint),
            ] else if (onTap != null && chevron) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: c.faint),
            ],
          ],
        ),
      ),
    );
  }
}

/// A round letter avatar in Garad purple.
class LetterAvatar extends StatelessWidget {
  const LetterAvatar({super.key, required this.name, this.size = 40});

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
      decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// One box in a [showFormSheet].
class FieldSpec {
  const FieldSpec({
    required this.label,
    this.initial = '',
    this.hint,
    this.obscure = false,
    this.keyboard,
    this.autofill,
    this.allow,
  });

  final String label;
  final String initial;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboard;
  final String? autofill;

  /// Only these characters can be typed.
  final RegExp? allow;
}

/// A bottom sheet with a title, boxes and one button. [submit] returns an error to show, or null when
/// done (an [ApiException]'s message is shown too). True when it finished.
Future<bool> showFormSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<FieldSpec> fields,
  required String action,
  bool danger = false,
  required Future<String?> Function(List<String> values) submit,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        _FormSheet(title: title, subtitle: subtitle, fields: fields, action: action, danger: danger, submit: submit),
  );
  return done == true;
}

class _FormSheet extends StatefulWidget {
  const _FormSheet({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.action,
    required this.danger,
    required this.submit,
  });

  final String title;
  final String? subtitle;
  final List<FieldSpec> fields;
  final String action;
  final bool danger;
  final Future<String?> Function(List<String> values) submit;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  late final _controllers = [for (final f in widget.fields) TextEditingController(text: f.initial)];
  late final _hidden = [for (final f in widget.fields) f.obscure];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.submit([for (final controller in _controllers) controller.text]);
    } on ApiException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(context);
    final accent = widget.danger ? c.danger : c.brand;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w600),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 6),
                Text(widget.subtitle!, style: TextStyle(color: c.muted, fontSize: 14, height: 1.4)),
              ],
              const SizedBox(height: 16),
              for (var i = 0; i < widget.fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                TextField(
                  controller: _controllers[i],
                  enabled: !_busy,
                  autofocus: i == 0,
                  obscureText: _hidden[i],
                  keyboardType: widget.fields[i].keyboard,
                  autofillHints: [?widget.fields[i].autofill],
                  inputFormatters: [
                    if (widget.fields[i].allow case final allow?) FilteringTextInputFormatter.allow(allow),
                  ],
                  textInputAction: i == widget.fields.length - 1 ? TextInputAction.done : TextInputAction.next,
                  onSubmitted: i == widget.fields.length - 1 ? (_) => _go() : null,
                  decoration: InputDecoration(
                    labelText: widget.fields[i].label,
                    hintText: widget.fields[i].hint,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    suffixIcon: widget.fields[i].obscure
                        ? IconButton(
                            onPressed: () => setState(() => _hidden[i] = !_hidden[i]),
                            icon: Icon(_hidden[i] ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          )
                        : null,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: c.danger, fontSize: 13.5)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : _go,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: accent.withValues(alpha: 0.4),
                    shape: const StadiumBorder(),
                  ),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(widget.action, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
