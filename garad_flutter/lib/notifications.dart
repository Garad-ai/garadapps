import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_storage.dart';

/// Settings → Notifications, like ChatGPT's "Responses": a phone notification when Garad finishes an
/// answer while the app is in the background (you switched to another app while it was writing).
/// Android only; nothing leaves the phone (no push server).
class GaradNotifications {
  GaradNotifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _storage = AppStorage();
  static const _responsesKey = 'garad_notify_responses';
  static bool _ready = false;

  /// On unless turned off in Settings (the phone may still block notifications for the app).
  static final responses = ValueNotifier<bool>(true);

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Once at start-up.
  static Future<void> init() async {
    try {
      responses.value = await _storage.read(key: _responsesKey) != 'off';
    } catch (_) {}
    if (!supported || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_garad')),
      );
      _ready = true;
    } catch (_) {
      // No notifications on this phone: the app works the same without them.
    }
  }

  /// Whether the phone lets Garad show notifications (Android 13+ asks the user).
  static Future<bool> allowedByPhone() async {
    if (!_ready) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the phone for permission (Android 13+). True when notifications can be shown.
  static Future<bool> askPhone() async {
    if (!_ready) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setResponses(bool on) async {
    responses.value = on;
    try {
      await _storage.write(key: _responsesKey, value: on ? 'on' : 'off');
    } catch (_) {}
  }

  /// An answer finished. Shown only when it's turned on and the app isn't on screen.
  static Future<void> answerReady({required String chatTitle, required String answer}) async {
    if (!_ready || !responses.value) return;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return;
    final text = plainPreview(answer);
    if (text.isEmpty) return;
    try {
      await _plugin.show(
        id: 1,
        title: chatTitle.trim().isEmpty ? 'Garad AI' : chatTitle.trim(),
        body: text,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'responses',
            'Responses',
            channelDescription: 'When Garad finishes an answer while you are in another app',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(''),
          ),
        ),
      );
    } catch (_) {}
  }

  /// The answer as one short plain line: no Markdown marks, code or hidden Garad tags.
  @visibleForTesting
  static String plainPreview(String answer) {
    final text = answer
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'\[\[[^\]]*\]\]'), ' ')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
        .replaceAll(RegExp(r'[#*_`>|~]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.length > 180 ? '${text.substring(0, 179).trimRight()}…' : text;
  }
}
