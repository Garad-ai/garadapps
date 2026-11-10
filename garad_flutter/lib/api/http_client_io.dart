import 'package:http/http.dart' as http;

/// Phones and desktop: the normal client (already streams).
http.Client createHttpClient() => http.Client();
