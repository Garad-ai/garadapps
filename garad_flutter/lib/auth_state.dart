import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:garad_ai/app_storage.dart';

import 'api/garad_api.dart';
import 'api/models.dart';
import 'google_login.dart';

/// Who is signed in. The login token is kept in the phone's secure storage (Keychain / Keystore).
class AuthState extends ChangeNotifier {
  AuthState(this.api) {
    api.onUnauthorized = _signedOutByServer;
  }

  final GaradApi api;

  static const _storage = AppStorage();
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
    // Not signed in: the welcome screen (Google, Apple, email or Skip), like ChatGPT.
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

  /// Sign in with email and password, like garad.ai.
  Future<void> login(String email, String password) async {
    final result = await api.login(email.trim().toLowerCase(), password);
    await _save(result.token, result.user);
  }

  /// The password reset link opened the app: the new password is saved and this phone is signed in.
  Future<void> resetPassword({required String code, required String password}) async {
    final result = await api.resetPassword(code: code, password: password);
    await _save(result.token, result.user);
  }

  /// Sign up: full name, email and password, like garad.ai (one Full name box).
  Future<void> register({required String fullName, required String email, required String password}) async {
    final result = await api.register(
      fullName: fullName.trim().replaceAll(RegExp(r'\s+'), ' '),
      email: email.trim().toLowerCase(),
      password: password,
    );
    await _save(result.token, result.user);
  }

  /// "Continue with Google": the phone's Google account picker, then the server checks the Google ID
  /// token and signs in (the same account as "Login with Google" on garad.ai). Returns false if the
  /// user closed the picker; throws [ApiException] with a message to show otherwise.
  Future<bool> signInWithGoogle() async {
    if (!GoogleLogin.supported) throw ApiException(GoogleLogin.text.notAvailable);
    final clientId = await api.googleClientId();
    if (clientId == null) throw ApiException(GoogleLogin.text.notAvailable);
    final String idToken;
    try {
      final token = await GoogleLogin.idToken(clientId);
      if (token == null) return false; // closed the account picker
      idToken = token;
    } on GoogleLoginFailed catch (e) {
      throw ApiException(e.message);
    }
    final result = await api.googleLogin(idToken);
    await _save(result.token, result.user);
    return true;
  }

  /// A fresh Google sign-in that proves the account's owner is here (Settings: set a password or
  /// delete an account made with Google). The ID token, or null if the user closed the account
  /// picker; throws [ApiException] with a message to show otherwise.
  Future<String?> confirmWithGoogle() async {
    if (!GoogleLogin.supported) throw ApiException(GoogleLogin.text.notAvailable);
    final clientId = await api.googleClientId();
    if (clientId == null) throw ApiException(GoogleLogin.text.notAvailable);
    try {
      return await GoogleLogin.idToken(clientId);
    } on GoogleLoginFailed catch (e) {
      throw ApiException(e.message);
    }
  }

  /// Settings → Profile: saves the new name and phone on the server, then here.
  Future<void> updateProfile({required String fullName, required String phone}) async {
    final updated = await api.updateProfile(
      fullName: fullName.trim().replaceAll(RegExp(r'\s+'), ' '),
      phone: phone.trim(),
    );
    user = updated;
    try {
      await _storage.write(key: _userKey, value: jsonEncode(updated.toJson()));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      // Signing out locally is what matters; the server token expires unused.
    }
    // Forget the Google account choice too, so the next "Continue with Google" asks which account.
    await GoogleLogin.signOut();
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
