import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

/// Settings managed in Garad admin › Settings › Mobile App (GET /api/mobile-app/config).
class AppConfig {
  const AppConfig({
    this.latestVersion,
    this.minimumVersion,
    this.androidUpdateUrl,
    this.iosUpdateUrl,
    this.updateMessage,
    this.maintenance = false,
    this.maintenanceMessage,
    this.announcement,
    this.links = const [],
  });

  factory AppConfig.fromJson(Map<String, Object?> data) {
    final update = data['update'] is Map ? data['update']! as Map : const {};
    final maintenance = data['maintenance'] is Map ? data['maintenance']! as Map : const {};
    final announcement = data['announcement'] is Map ? data['announcement']! as Map : null;
    final message = _text(announcement?['message']);
    return AppConfig(
      latestVersion: _text(data['latestVersion']),
      minimumVersion: _text(data['minimumVersion']),
      androidUpdateUrl: _text(update['androidUrl']),
      iosUpdateUrl: _text(update['iosUrl']),
      updateMessage: _text(update['message']),
      maintenance: maintenance['enabled'] == true,
      maintenanceMessage: _text(maintenance['message']),
      announcement: message != null ? Announcement(message, _text(announcement!['url'])) : null,
      links: [
        for (final link in (data['links'] is List ? data['links']! as List : const []))
          if (link is Map && link['label'] is String && link['url'] is String)
            AppLink(link['label'] as String, link['url'] as String),
      ],
    );
  }

  /// A setting left blank in the admin (or not a string) counts as unset, so the app falls back
  /// to its own default text instead of showing an empty message or a dead link.
  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  final String? latestVersion;
  final String? minimumVersion;
  final String? androidUpdateUrl;
  final String? iosUpdateUrl;
  final String? updateMessage;
  final bool maintenance;
  final String? maintenanceMessage;
  final Announcement? announcement;
  final List<AppLink> links;

  /// Where to send the user to update on this platform, if the admin set it.
  String? get updateUrl => defaultTargetPlatform == TargetPlatform.iOS ? iosUpdateUrl : androidUpdateUrl;
}

class Announcement {
  const Announcement(this.message, this.url);
  final String message;
  final String? url;
}

class AppLink {
  const AppLink(this.label, this.url);
  final String label;
  final String url;
}

enum UpdateStatus { required, available, none }

/// Compares dotted versions numerically: -1, 0 or 1.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final left = parts(a);
  final right = parts(b);
  for (var i = 0; i < (left.length > right.length ? left.length : right.length); i++) {
    final diff = (i < left.length ? left[i] : 0) - (i < right.length ? right[i] : 0);
    if (diff != 0) return diff > 0 ? 1 : -1;
  }
  return 0;
}

UpdateStatus updateStatus(AppConfig? config, String appVersion) {
  if (config == null) return UpdateStatus.none;
  final minimum = config.minimumVersion;
  if (minimum != null && compareVersions(appVersion, minimum) < 0) return UpdateStatus.required;
  final latest = config.latestVersion;
  if (latest != null && compareVersions(appVersion, latest) < 0) return UpdateStatus.available;
  return UpdateStatus.none;
}

/// Loads the admin's app settings; null when offline or the site is unreachable.
Future<AppConfig?> fetchAppConfig({Duration timeout = const Duration(seconds: 6)}) async {
  try {
    final response = await http
        .get(Uri.parse('$siteUrl/api/mobile-app/config'), headers: {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    return data is Map<String, Object?> ? AppConfig.fromJson(data) : null;
  } catch (_) {
    return null;
  }
}
