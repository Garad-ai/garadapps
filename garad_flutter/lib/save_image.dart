/// Saves an image for the user: to the phone's photo gallery, or as a download in a browser.
library;

export 'save_image_io.dart' if (dart.library.js_interop) 'save_image_web.dart';
