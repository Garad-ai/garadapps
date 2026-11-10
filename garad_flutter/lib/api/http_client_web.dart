import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// Browsers: `fetch`, which delivers a streamed reply as it arrives (the default browser client
/// waits for the whole reply).
http.Client createHttpClient() => FetchClient(mode: RequestMode.cors);
