/// Where the app points. Override at build time, for example for the local XAMPP site:
///
///   flutter run --dart-define=SITE_URL=http://10.0.2.2/garad.ai/public
const String _siteUrlSetting = String.fromEnvironment('SITE_URL', defaultValue: 'https://garad.ai');
const String _startPath = String.fromEnvironment('START_PATH', defaultValue: '/chat');

/// The Garad AI website the app shows, e.g. https://garad.ai (no trailing slash).
final String siteUrl = _siteUrlSetting.replaceAll(RegExp(r'/+$'), '');

/// First page the app opens: the Chat Pro web app.
final String startUrl = '$siteUrl$_startPath';

final String _siteHost = Uri.parse(siteUrl).host.replaceFirst(RegExp(r'^www\.'), '');

/// True for the site's host and its subdomains; everything else opens outside the app.
bool isSiteUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return false;
  return host == _siteHost || host.endsWith('.$_siteHost');
}

/// Adds `voice=1`, which makes Chat Pro open straight into Garad Voice.
String withVoice(String url) => '$url${url.contains('?') ? '&' : '?'}voice=1';
