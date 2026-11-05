import 'dart:convert';

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
    notifyListeners();
  }

  Future<void> _save(String token, GaradUser newUser, {bool remember = true}) async {
    api.token = token;
    user = newUser;
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
    user = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } catch (_) {}
  }
}
