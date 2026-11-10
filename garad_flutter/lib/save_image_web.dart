import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Browsers: a normal file download.
Future<void> saveImage(Uint8List bytes, String name) async {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
  (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = name
    ..click();
  // Let the download start before the temporary link is freed.
  Future.delayed(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}
