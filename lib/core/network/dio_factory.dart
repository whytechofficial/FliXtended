import 'package:dio/dio.dart';
import 'package:flixquest/core/cache/cache_interceptor.dart';
import 'package:flixquest/core/cache/http_cache.dart';
import 'package:flutter/foundation.dart';

import 'interceptors/error_interceptor.dart';
import 'interceptors/header_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'interceptors/single_flight_interceptor.dart';
import 'interceptors/tmdb_proxy_interceptor.dart';

/// The public (TMDB) Dio client.
///
/// Adapted from upstream 4.3.0: the Laravel client half and the
/// `AppEnvironment` dependency are dropped. FliXtended stays on Firebase and
/// needs no backend URL, so the timeouts are plain values (10s connect,
/// 20s receive — the same defaults upstream's `AppEnvironment` supplied).
Dio createPublicDio({
  Dio? dio,
  HttpCache? httpCache,
  bool? debugLogging,
  Duration connectTimeout = const Duration(seconds: 10),
  Duration receiveTimeout = const Duration(seconds: 20),
  Future<void> Function(Duration)? retryDelay,
}) =>
    _create(
      dio: dio,
      httpCache: httpCache,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      debugLogging: debugLogging,
      retryDelay: retryDelay,
    );

Dio _create({
  Dio? dio,
  HttpCache? httpCache,
  String? scope,
  Duration connectTimeout = const Duration(seconds: 10),
  Duration receiveTimeout = const Duration(seconds: 20),
  bool? debugLogging,
  Future<void> Function(Duration)? retryDelay,
}) {
  final client = dio ?? Dio();
  client.options.connectTimeout = connectTimeout;
  client.options.receiveTimeout = receiveTimeout;
  if (client.interceptors.any((interceptor) => interceptor is HeaderInterceptor)) {
    return client;
  }
  client.interceptors.add(HeaderInterceptor());
  client.interceptors.add(TmdbProxyInterceptor());
  if (httpCache != null) {
    client.interceptors.add(SingleFlightInterceptor(client, defaultScope: scope));
  }
  client.interceptors.add(RetryInterceptor(client, delay: retryDelay));
  if (httpCache != null) {
    client.interceptors.add(CacheInterceptor(client, httpCache, defaultScope: scope));
  }
  if (kDebugMode && (debugLogging ?? true)) {
    client.interceptors.add(LoggingInterceptor());
  }
  client.interceptors.add(ErrorInterceptor());
  return client;
}
