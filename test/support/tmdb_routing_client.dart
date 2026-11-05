import 'package:flixquest/constants/api_constants.dart';
import 'package:http/http.dart' as http;

/// Routes the real TMDB HTTP client to a local dependency fixture. Requests to
/// the proxy keep their complete destination query, including reserved text.
class TmdbRoutingClient extends http.BaseClient {
  TmdbRoutingClient(this.directBase);

  final Uri directBase;
  final http.Client _transport = http.Client();

  /// Hosts whose traffic belongs to TMDB: the public API host the tests
  /// were written against, and the worker the app actually uses as its
  /// TMDB base URL today. Without the second, probes and searches escape
  /// to the real worker and the fixture never sees them.
  static bool _isTmdbHost(String host) =>
      host == 'api.themoviedb.org' ||
      host == Uri.parse(TMDB_API_BASE_URL).host;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!_isTmdbHost(request.url.host)) {
      return _transport.send(request);
    }
    final uri = directBase.replace(
      path: '${directBase.path}${request.url.path}',
      query: request.url.query,
    );
    return _transport.send(http.Request(request.method, uri)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects);
  }

  @override
  void close() => _transport.close();
}
