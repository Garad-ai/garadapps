/// Errors reported by a preview of an app the AI built. Browsers: the preview is an iframe that posts
/// `{garadAppError: "…"}` to this page. Phones: the web view calls a JavaScript handler instead, so
/// nothing is needed here.
library;

export 'app_messages_io.dart' if (dart.library.js_interop) 'app_messages_web.dart';
