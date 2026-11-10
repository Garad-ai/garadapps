/// Images pasted into the app (Ctrl+V / ⌘V). Browsers: from the page's paste event. Phones: nothing
/// here — Android keyboards insert images through the text field itself (contentInsertionConfiguration).
library;

export 'paste_image_io.dart' if (dart.library.js_interop) 'paste_image_web.dart';
