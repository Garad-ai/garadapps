/// Keeps the browser's own colour (Safari's top edge behind the clock, the page background) in
/// step with the screen being shown, so no white band covers the app's top buttons.
/// Phones and desktop have no browser around the app, so this does nothing there.
library;

export 'browser_color_io.dart' if (dart.library.js_interop) 'browser_color_web.dart';
