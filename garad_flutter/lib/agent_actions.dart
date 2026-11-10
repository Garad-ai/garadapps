import 'package:flutter/foundation.dart';
import 'package:garad_agent/garad_agent.dart';
import 'package:url_launcher/url_launcher.dart';

/// Phone actions requested by Garad Voice (see GARAD_APP_TOOLS in the web project's
/// frontend/src/core/appShell.ts). Each action only opens something on the phone; calls and
/// messages open ready for the user to press call or send. Messages go back to the model,
/// which tells the user in their language.
typedef ActionResult = Map<String, Object?>;

ActionResult _result(bool ok, String message) => {'ok': ok, 'message': message};

String _text(Object? value) => value is String ? value.trim() : '';

/// Keeps digits and a leading +.
String _phoneNumber(Object? value) {
  final raw = _text(value);
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return raw.startsWith('+') && digits.isNotEmpty ? '+$digits' : digits;
}

String _encode(String value) => Uri.encodeComponent(value);

bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

/// Opens the first link the phone can handle: the app first, then its website.
Future<bool> _openFirst(List<String> urls) async {
  for (final url in urls) {
    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) return true;
    } catch (_) {
      // Not installed or not supported: try the next link.
    }
  }
  return false;
}

final Map<String, List<String> Function(String search)> _appLinks = {
  'whatsapp': (_) => ['whatsapp://send', 'https://wa.me/'],
  'facebook': (_) => ['fb://feed', 'https://www.facebook.com'],
  'messenger': (_) => ['fb-messenger://', 'https://www.messenger.com'],
  'instagram': (_) => ['instagram://app', 'https://www.instagram.com'],
  'tiktok': (search) => search.isNotEmpty
      ? ['https://www.tiktok.com/search?q=${_encode(search)}']
      : ['snssdk1233://', 'https://www.tiktok.com'],
  'youtube': (search) => search.isNotEmpty
      ? ['https://www.youtube.com/results?search_query=${_encode(search)}']
      : ['vnd.youtube://', 'https://www.youtube.com'],
  'telegram': (_) => ['tg://', 'https://t.me'],
  'x': (_) => ['twitter://timeline', 'https://x.com'],
  'snapchat': (_) => ['snapchat://', 'https://www.snapchat.com'],
  'gmail': (_) => ['googlegmail://', 'https://mail.google.com'],
  'maps': (search) => [
    _isIOS ? 'maps://?q=${_encode(search)}' : 'geo:0,0?q=${_encode(search)}',
    'https://www.google.com/maps/search/?api=1&query=${_encode(search)}',
  ],
  'phone': (_) => ['tel:'],
  'messages': (_) => ['sms:'],
  'play_store': (search) => [
    'market://search?q=${_encode(search)}&c=apps',
    'https://play.google.com/store/search?q=${_encode(search)}&c=apps',
  ],
};

Future<ActionResult> runAgentAction(String name, Map<String, Object?> args) async {
  switch (name) {
    case 'open_app':
      final app = _text(args['app']).toLowerCase();
      if (app == 'settings') {
        return await GaradAgent.openAppSettings()
            ? _result(true, 'Opened the phone settings for Garad AI.')
            : _result(false, 'Opening the settings is not supported on this phone.');
      }
      final links = _appLinks[app];
      if (links == null) return _result(false, 'Opening "$app" is not supported yet.');
      return await _openFirst(links(_text(args['search'])))
          ? _result(true, 'Opened $app.')
          : _result(false, 'Could not open $app on this phone.');

    case 'open_website':
      var url = _text(args['url']);
      if (url.isNotEmpty && !RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) url = 'https://$url';
      if (!RegExp(r'^https?://\S+\.\S+', caseSensitive: false).hasMatch(url)) {
        return _result(false, 'That website address is not valid.');
      }
      return await _openFirst([url]) ? _result(true, 'Opened $url.') : _result(false, 'Could not open the website.');

    case 'call_phone':
      final number = _phoneNumber(args['phone_number']);
      if (number.replaceAll('+', '').length < 3) return _result(false, 'The phone number is missing or too short.');
      return await _openFirst(['tel:$number'])
          ? _result(true, 'The dialer is open with $number; the user presses call.')
          : _result(false, 'This phone cannot make calls.');

    case 'send_whatsapp_message':
      final number = _phoneNumber(args['phone_number']).replaceAll('+', '');
      final message = _encode(_text(args['message']));
      final opened = await _openFirst(
        number.isNotEmpty
            ? ['whatsapp://send?phone=$number&text=$message', 'https://wa.me/$number?text=$message']
            : ['whatsapp://send?text=$message', 'https://wa.me/?text=$message'],
      );
      if (!opened) return _result(false, 'WhatsApp could not be opened on this phone.');
      return _result(
        true,
        number.isNotEmpty
            ? 'WhatsApp is open with the message ready; the user presses send.'
            : 'WhatsApp is open with the message ready; the user picks the chat and presses send.',
      );

    case 'send_sms':
      final number = _phoneNumber(args['phone_number']);
      final body = _encode(_text(args['message']));
      return await _openFirst(['sms:$number${_isIOS ? '&' : '?'}body=$body'])
          ? _result(true, 'The messages app is open with the SMS ready; the user presses send.')
          : _result(false, 'The messages app could not be opened.');

    case 'navigate_to':
      final destination = _text(args['destination']);
      if (destination.isEmpty) return _result(false, 'The destination is missing.');
      final opened = await _openFirst([
        _isIOS ? 'maps://?daddr=${_encode(destination)}' : 'google.navigation:q=${_encode(destination)}',
        'https://www.google.com/maps/dir/?api=1&destination=${_encode(destination)}',
      ]);
      return opened
          ? _result(true, 'Directions to $destination are open.')
          : _result(false, 'The maps app could not be opened.');

    default:
      return _result(false, 'The action "$name" is not supported.');
  }
}
