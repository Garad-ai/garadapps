/// Browsers: plain localStorage, used only on http pages where secure storage cannot work.
library;

import 'package:web/web.dart' as web;

bool get needed => !web.window.isSecureContext;

String? read(String key) => web.window.localStorage.getItem(key);

void write(String key, String value) => web.window.localStorage.setItem(key, value);

void delete(String key) => web.window.localStorage.removeItem(key);
