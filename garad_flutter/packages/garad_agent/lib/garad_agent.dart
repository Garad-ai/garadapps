/// The Garad agent: an Android AccessibilityService that reads the app in front and acts on
/// it when Garad Voice asks (see docs/AGENT_PLAN.md in the repo root). On iOS and the web the
/// native side does not exist, so everything reports "unsupported".
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('ai.garad/agent');

/// What a screen action tells Garad Voice; `screen` describes the screen after it.
typedef AgentResult = Map<String, Object?>;

/// Actions carried out natively (AgentController.kt): the screen through the accessibility
/// service, messages and calls through notification access, and Voice bookkeeping.
const Set<String> screenActions = {
  'read_screen',
  'tap',
  'type_text',
  'scroll',
  'phone_button',
  'confirm_action',
  'stop',
  'read_messages',
  'reply_to_message',
  'answer_call',
  'decline_call',
  'voice_session',
};

/// One visible element of the app in front.
class ScreenElement {
  ScreenElement.fromMap(Map<Object?, Object?> map)
      : id = (map['id'] as num?)?.toInt() ?? 0,
        role = map['role'] as String?,
        text = map['text'] as String?,
        description = map['description'] as String?,
        clickable = map['clickable'] == true,
        editable = map['editable'] == true;

  final int id;
  final String? role;
  final String? text;
  final String? description;
  final bool clickable;
  final bool editable;
}

/// The result of reading the screen: the elements, or the reason it could not be read
/// (`unsupported`, `not_enabled`, `no_window` or `blocked_app`).
class ScreenReadResult {
  ScreenReadResult.unavailable(this.reason)
      : available = false,
        packageName = null,
        elements = const [],
        truncated = false;

  ScreenReadResult.fromMap(Map<Object?, Object?> map)
      : available = map['available'] == true,
        reason = map['reason'] as String?,
        packageName = map['package'] as String?,
        truncated = map['truncated'] == true,
        elements = [
          for (final item in (map['elements'] as List<Object?>? ?? const []))
            if (item is Map) ScreenElement.fromMap(item),
        ];

  final bool available;
  final String? reason;
  final String? packageName;
  final List<ScreenElement> elements;
  final bool truncated;
}

class GaradAgent {
  GaradAgent._();

  /// True on builds that include the agent (Android only).
  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> _bool(String method) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(method) ?? false;
  }

  /// The user has turned Garad on in the phone's Accessibility settings.
  static Future<bool> isEnabled() => _bool('isEnabled');

  /// The service is on and running right now.
  static Future<bool> isConnected() => _bool('isConnected');

  /// Garad may read message and call notifications (a separate switch in the phone settings).
  static Future<bool> isNotificationAccessEnabled() => _bool('isNotificationAccessEnabled');

  /// Read new messages and calls aloud while Garad Voice is closed (off by default).
  static Future<bool> getAnnounceAloud() => _bool('getAnnounceAloud');

  static Future<void> setAnnounceAloud(bool value) async {
    if (isSupported) await _channel.invokeMethod<void>('setAnnounceAloud', value);
  }

  /// Opens the phone's Accessibility settings, where the user turns Garad on or off.
  static Future<void> openSettings() async {
    if (isSupported) await _channel.invokeMethod<void>('openSettings');
  }

  /// Opens the phone's notification access settings.
  static Future<void> openNotificationSettings() async {
    if (isSupported) await _channel.invokeMethod<void>('openNotificationSettings');
  }

  /// Opens this app's page in the phone settings.
  static Future<bool> openAppSettings() async {
    if (!isSupported) return false;
    await _channel.invokeMethod<void>('openAppSettings');
    return true;
  }

  /// Turns the agent off straight away. Turning it on always goes through the settings screen.
  static Future<void> disable() async {
    if (isSupported) await _channel.invokeMethod<void>('disable');
  }

  /// Runs a screen action requested by Garad Voice. Safety rules are enforced natively.
  static Future<AgentResult> perform(String name, Map<String, Object?> args) async {
    if (!isSupported) {
      return {'ok': false, 'message': 'Screen actions are only available in the Android app.'};
    }
    final result = await _channel.invokeMapMethod<String, Object?>('perform', {'name': name, 'args': args});
    return result ?? {'ok': false, 'message': 'The action failed on the phone.'};
  }

  /// Runs a script in the Garad web page natively, which also works while the app is in the
  /// background (when the agent is working in another app). Returns false when unsupported.
  static Future<bool> evaluateInPage(String script) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('evaluateInPage', script) ?? false;
  }

  /// Reads the app in front. [delay] (up to 30 s) waits natively first, so the user can
  /// switch to another app.
  static Future<ScreenReadResult> readScreen([Duration delay = Duration.zero]) async {
    if (!isSupported) return ScreenReadResult.unavailable('unsupported');
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('readScreen', delay.inMilliseconds);
    return map == null ? ScreenReadResult.unavailable('not_enabled') : ScreenReadResult.fromMap(map);
  }
}
