import 'dart:convert';

import 'package:http/http.dart' as http;

import '../catalog/media_item.dart';
import '../constants/api_constants.dart';
import '../models/named_list.dart';
import 'tmdb_connectivity.dart';

/// A public TMDB list, read from its link: no backend, no account, just
/// the list's own page. `https://www.themoviedb.org/list/12345-my-list`
/// names list 12345; the slug after the id is decoration.
class TmdbListImport {
  const TmdbListImport._();

  /// The list id in [value], or null when it is not a TMDB list address.
  /// The host must be themoviedb.org itself (a www. in front is the same
  /// site); a lookalike host is not read.
  static int? parseId(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final absolute =
        text.toLowerCase().startsWith('http') ? text : 'https://$text';
    final uri = Uri.tryParse(absolute);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    if (host != 'themoviedb.org' && host != 'www.themoviedb.org') {
      return null;
    }
    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length < 2 || segments[0].toLowerCase() != 'list') {
      return null;
    }
    final match = RegExp(r'^(\d+)').firstMatch(segments[1]);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Fetches list [listId] from TMDB and reads its titles. [fetch] is the
  /// transport, defaulting to the app's TMDB route (proxy-aware); tests
  /// stand in with canned responses. Throws [TmdbListImportException]
  /// for a link that is not a list, a failed fetch, or a list with no
  /// titles in it.
  static Future<TmdbListImportResult> fetchList(
    int listId, {
    String proxyUrl = '',
    Future<http.Response> Function(String url, String proxyUrl)? fetch,
  }) async {
    final send = fetch ??
        (String url, String proxy) =>
            TmdbConnectivity.instance.get(url, proxy);
    final response = await send(
      '$TMDB_API_BASE_URL/list/$listId?api_key=$TMDB_API_KEY&language=en-US',
      proxyUrl,
    );
    if (response.statusCode != 200) {
      throw const TmdbListImportException(TmdbListImportError.fetchFailed);
    }
    final body = jsonDecode(response.body);
    if (body is! Map) {
      throw const TmdbListImportException(TmdbListImportError.fetchFailed);
    }
    final items = itemsFromJson(body['items']);
    if (items.isEmpty) {
      throw const TmdbListImportException(TmdbListImportError.emptyList);
    }
    final name = body['name'];
    return TmdbListImportResult(
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'Imported list',
      items: items,
    );
  }

  /// The titles in a TMDB list response. People are skipped — a list is
  /// titles, and a person has no row in one — as is anything without an
  /// id or a media type the app knows.
  static List<NamedListItem> itemsFromJson(Object? json) {
    if (json is! List) return const <NamedListItem>[];
    final now = DateTime.now().toString();
    final items = <NamedListItem>[];
    for (final entry in json) {
      if (entry is! Map) continue;
      final mediaType = entry['media_type'];
      final kind = switch (mediaType) {
        'movie' => MediaKind.movie,
        'tv' => MediaKind.series,
        _ => null,
      };
      if (kind == null) continue;
      final id = entry['id'];
      if (id is! int) continue;
      final title = kind == MediaKind.movie
          ? entry['title'] as String?
          : entry['name'] as String?;
      if (title == null || title.isEmpty) continue;
      final rating = entry['vote_average'];
      items.add(
        NamedListItem(
          kind: kind,
          tmdbId: id,
          title: title,
          posterPath: entry['poster_path'] as String?,
          backdropPath: entry['backdrop_path'] as String?,
          overview: entry['overview'] as String?,
          releaseDate: (kind == MediaKind.movie
              ? entry['release_date']
              : entry['first_air_date']) as String?,
          rating: rating is num ? rating.toDouble() : null,
          dateAdded: now,
        ),
      );
    }
    return items;
  }
}

class TmdbListImportResult {
  const TmdbListImportResult({required this.name, required this.items});

  final String name;
  final List<NamedListItem> items;
}

enum TmdbListImportError { invalidLink, fetchFailed, emptyList }

class TmdbListImportException implements Exception {
  const TmdbListImportException(this.error);

  final TmdbListImportError error;
}
