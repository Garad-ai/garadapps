import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Browsers: `{garadAppError: "…"}` posted by the preview iframe. Returns a function that stops listening.
void Function() listenForAppErrors(void Function(String message) onError) {
  void onMessage(web.MessageEvent event) {
    final data = event.data;
    if (data == null || !data.isA<JSObject>()) return;
    final error = (data as JSObject)['garadAppError'];
    if (error != null && error.isA<JSString>()) onError((error as JSString).toDart);
  }

  final listener = onMessage.toJS;
  web.window.addEventListener('message', listener);
  return () => web.window.removeEventListener('message', listener);
}

/// Browsers: `{<key>: "…"}` posted by an iframe (e.g. a code run's output). Returns a function that
/// stops listening.
void Function() listenForWebMessages(String key, void Function(String message) onMessage) {
  void handle(web.MessageEvent event) {
    final data = event.data;
    if (data == null || !data.isA<JSObject>()) return;
    final value = (data as JSObject)[key];
    if (value != null && value.isA<JSString>()) onMessage((value as JSString).toDart);
  }

  final listener = handle.toJS;
  web.window.addEventListener('message', listener);
  return () => web.window.removeEventListener('message', listener);
}
