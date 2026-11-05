import 'package:flutter/material.dart';

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
}
