import 'dart:typed_data';

import 'package:gal/gal.dart';

/// Phones: into the photo gallery (asks for permission the first time). Throws if it cannot.
Future<void> saveImage(Uint8List bytes, String name) async {
  if (!await Gal.hasAccess() && !await Gal.requestAccess()) throw StateError('no access');
  await Gal.putImageBytes(bytes, name: name);
}
