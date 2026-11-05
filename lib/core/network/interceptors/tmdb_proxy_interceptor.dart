import 'package:dio/dio.dart';
import 'package:flixquest/constants/api_constants.dart';
import 'package:flixquest/functions/tmdb_request.dart';

class TmdbProxyInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final request = options;
    // TMDB traffic is the public API host or the worker the app uses as its
    // TMDB base today; checking only the public host silently dropped the
    // proxy for every Dio-based TMDB call after the worker migration.
    final tmdbHost = Uri.parse(TMDB_API_BASE_URL).host;
    if (request.extra['tmdbOriginalUrl'] == null &&
        (request.uri.host == 'api.themoviedb.org' ||
            request.uri.host == tmdbHost) &&
        request.extra['tmdbProxyEnabled'] == true) {
      final proxy = request.extra['tmdbProxyUrl'] as String? ?? '';
      if (proxy.isNotEmpty) {
        final original = request.uri.toString();
        request.extra['tmdbOriginalUrl'] = original;
        request.path = tmdbRequestUri(original, true, proxy).toString();
        request.baseUrl = '';
        request.queryParameters = {};
      }
    }
    handler.next(request);
  }
}
