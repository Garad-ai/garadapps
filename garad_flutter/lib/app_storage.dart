/// Saved login and settings.
///
/// Secure storage wherever it works. Browsers turn off the encryption it needs on plain http
/// pages (for example the app opened on an iPhone over Wi-Fi), so there it falls back to the
/// browser's normal storage instead of failing and leaving a white screen.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'plain_storage_io.dart' if (dart.library.js_interop) 'plain_storage_web.dart' as plain;

class AppStorage {
  const AppStorage();

  static const _secure = FlutterSecureStorage();

  Future<String?> read({required String key}) async =>
      plain.needed ? plain.read(key) : _secure.read(key: key);

  Future<void> write({required String key, required String? value}) async {
    if (value == null) return delete(key: key);
    if (plain.needed) return plain.write(key, value);
    await _secure.write(key: key, value: value);
  }

  Future<void> delete({required String key}) async =>
      plain.needed ? plain.delete(key) : _secure.delete(key: key);
}
