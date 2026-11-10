/// Phones: errors arrive through the web view's JavaScript handler. Returns a function that stops listening.
void Function() listenForAppErrors(void Function(String message) onError) => () {};

/// Phones: messages arrive through the web view's JavaScript handler. Returns a function that stops listening.
void Function() listenForWebMessages(String key, void Function(String message) onMessage) => () {};
