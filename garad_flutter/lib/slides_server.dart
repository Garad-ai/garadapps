import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Serves the slide viewer (assets/slides, built from slides_viewer/) to the web view over
/// http://127.0.0.1. The viewer's parser runs in a worker with WebAssembly, which a web view will not
/// load from file:// pages. Only the viewer's own files are served, only on this phone (loopback), on
/// a free port. The deck itself never goes through it: the page asks the app for it directly.
class SlidesServer {
  SlidesServer._();

  static const _root = 'assets/slides/';
  static HttpServer? _server;
  static Future<Uri>? _starting;

  /// The viewer page's address, starting the server the first time.
  static Future<Uri> url() => _starting ??= _start().catchError((Object e) {
    _starting = null; // try again next time
    throw e;
  });

  static Future<Uri> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle);
    return Uri(scheme: 'http', host: '127.0.0.1', port: server.port, path: '/index.html');
  }

  static Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final asset = request.method == 'GET' ? assetFor(request.uri.path) : null;
      if (asset == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final path = asset.substring(_root.length);
      final ByteData data;
      try {
        data = await rootBundle.load(asset);
      } catch (_) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      response.headers
        ..contentType = contentTypeFor(path)
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      response.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } finally {
      await response.close();
    }
  }

  /// The asset a request path stands for, or null: only plain names inside the viewer folder
  /// ("/index.html", "/assets/x.js"), never "..", "%2e%2e" or any other app asset.
  static String? assetFor(String requestPath) {
    final String path;
    try {
      path = Uri.decodeFull(requestPath).replaceFirst(RegExp(r'^/+'), '');
    } catch (_) {
      return null;
    }
    if (path.isEmpty || path.contains(r'\')) return null;
    if (path.split('/').any((p) => p.isEmpty || p == '..' || p == '.')) return null;
    return '$_root$path';
  }

  /// WebAssembly must be served as application/wasm to compile while it downloads.
  static ContentType contentTypeFor(String path) {
    final extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'html' => ContentType.html,
      'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'wasm' => ContentType('application', 'wasm'),
      'json' => ContentType.json,
      'svg' => ContentType('image', 'svg+xml'),
      'png' => ContentType('image', 'png'),
      'woff2' => ContentType('font', 'woff2'),
      _ => ContentType.binary,
    };
  }

  /// For tests.
  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _starting = null;
  }
}
