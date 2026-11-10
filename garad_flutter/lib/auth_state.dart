import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api/garad_api.dart';
import 'api/models.dart';

/// Who is signed in. The login token is kept in the phone's secure storage (Keychain / Keystore).
class AuthState extends ChangeNotifier {
  AuthState(this.api) {
    api.onUnauthorized = _signedOutByServer;
  }

  final GaradApi api;

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'garad_api_token';
  static const _userKey = 'garad_api_user';

  GaradUser? user;
  bool ready = false;

  bool get signedIn => user != null;

  /// Restores the last login. Works offline: the saved user is shown, then refreshed when online.
  Future<void> restore() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final savedUser = await _storage.read(key: _userKey);
      if (token != null && savedUser != null) {
        api.token = token;
        user = GaradUser.fromJson(jsonDecode(savedUser) as Map<String, dynamic>);
      }
    } catch (_) {
      // Unreadable storage (e.g. after an OS restore): start signed out.
      await _clear();
    }
    // First launch (never signed in or out): straight into the chat as a guest, like ChatGPT.
    // Offline or refused: the login screen, which also offers "Continue without an account".
    if (user == null && await _storage.read(key: _signedOutKey) == null) {
      try {
        await continueAsGuest();
      } on ApiException {
        // Show the login screen.
      }
    }
    ready = true;
    notifyListeners();

    if (user != null) {
      try {
        user = await api.me();
        await _storage.write(key: _userKey, value: jsonEncode(user!.toJson()));
        notifyListeners();
      } on ApiException {
        // Offline keeps the saved login; a 401 already signed out via onUnauthorized.
      }
    }
  }

  static const _deviceKey = 'garad_device_id';
  static const _signedOutKey = 'garad_signed_out';

  bool get isGuest => user?.guest ?? false;

  /// Chat without an account. One guest per phone (a random id kept on the phone), so its daily
  /// message limit carries over between app starts.
  Future<void> continueAsGuest() async {
    var deviceId = await _storage.read(key: _deviceKey);
    if (deviceId == null) {
      final random = Random.secure();
      deviceId = List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
      await _storage.write(key: _deviceKey, value: deviceId);
    }
    final result = await api.guest(deviceId);
    await _save(result.token, result.user);
  }

  /// A guest taps "Log in": the login / sign-up screen (the guest's chats stay with the guest).
  Future<void> leaveGuest() async {
    await _clear();
    await _storage.write(key: _signedOutKey, value: '1');
    notifyListeners();
  }

  /// [remember] false keeps the login only until the app is closed.
  Future<void> login(String email, String password, {bool remember = true}) async {
    final result = await api.login(email.trim(), password);
    await _save(result.token, result.user, remember: remember);
  }

  Future<void> register({
    required String name,
    required String surname,
    required String phone,
    required String country,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final result = await api.register(
      name: name.trim(),
      surname: surname.trim(),
      phone: phone.trim(),
      country: country.trim(),
      email: email.trim(),
      password: password,
      passwordConfirmation: passwordConfirmation,
    );
    await _save(result.token, result.user);
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      // Signing out locally is what matters; the server token expires unused.
    }
    await _clear();
    // Signed out on purpose: the next start shows the login screen, not a guest chat.
    await _storage.write(key: _signedOutKey, value: '1');
    notifyListeners();
  }

  Future<void> _save(String token, GaradUser newUser, {bool remember = true}) async {
    api.token = token;
    user = newUser;
    if (!newUser.guest) await _storage.delete(key: _signedOutKey);
    if (remember) {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _userKey, value: jsonEncode(newUser.toJson()));
    } else {
      // Not remembered: drop any older saved login so the next app start asks again.
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    }
    notifyListeners();
  }

  void _signedOutByServer() {
    if (user == null) return;
    _clear().then((_) => notifyListeners());
  }

  Future<void> _clear() async {
    api.token = null;
    api.clearCache();
    user = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } catch (_) {}
  }
}
