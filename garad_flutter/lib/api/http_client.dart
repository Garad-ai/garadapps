/// The HTTP client for the platform: the browser's `fetch` on the web (it streams replies piece
/// by piece, so voice mode can start speaking early), the normal client everywhere else.
library;

export 'http_client_io.dart' if (dart.library.js_interop) 'http_client_web.dart';
