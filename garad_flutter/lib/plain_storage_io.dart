/// Phones and desktop always have secure storage, so the plain fallback is never used there.
library;

const bool needed = false;

String? read(String key) => null;

void write(String key, String value) {}

void delete(String key) {}
