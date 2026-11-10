import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'remote_config.dart';

/// App-wide state: the admin's settings, dismissed notices, the theme the web page reports,
/// and "Talk to Garad" requests from the launcher shortcut.
class AppState extends ChangeNotifier {
  AppState({required this.appVersion});

  final String appVersion;

  AppConfig? config;
  bool updateDismissed = false;
  String? dismissedAnnouncement;

  /// The website reports its own theme, which can differ from the device setting.
  Color? pageBackground;
  bool? pageDark;

  /// Bumped for each `garadai://voice` link, so a repeat tap while open still works.
  int voiceRequest = 0;

  UpdateStatus get status => updateStatus(config, appVersion);

  Future<AppConfig?> loadConfig() async {
    final next = await fetchAppConfig();
    if (next != null) {
      config = next;
      notifyListeners();
    }
    return next;
  }

  void setPageTheme(Color background, bool dark) {
    if (pageBackground == background && pageDark == dark) return;
    pageBackground = background;
    pageDark = dark;
    notifyListeners();
  }

  void dismissUpdate([bool value = true]) {
    updateDismissed = value;
    notifyListeners();
  }

  void dismissAnnouncement(String message) {
    dismissedAnnouncement = message;
    notifyListeners();
  }

  void requestVoice() {
    voiceRequest++;
    notifyListeners();
  }

  // ---- Appearance (Settings → Light / Dark / System), remembered on this device ----

  static const _storage = FlutterSecureStorage();
  static const _themeKey = 'garad_theme_mode';

  ThemeMode themeMode = ThemeMode.system;

  Future<void> loadThemeMode() async {
    try {
      final saved = await _storage.read(key: _themeKey);
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      if (mode != null && mode != themeMode) {
        themeMode = mode;
        notifyListeners();
      }
    } catch (_) {
      // Unreadable storage: keep following the phone's setting.
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == themeMode) return;
    themeMode = mode;
    notifyListeners();
    _storage.write(key: _themeKey, value: mode.name).catchError((_) {});
  }
}
