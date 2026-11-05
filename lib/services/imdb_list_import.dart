import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../catalog/media_item.dart';
import '../constants/api_constants.dart';
import '../models/named_list.dart';
import 'tmdb_connectivity.dart';
import 'tmdb_list_import.dart';

/// A public IMDb list, read from its link: no account, just the list's
/// own page. `https://www.imdb.com/list/ls123456789/` names list
/// ls123456789; anything after the id is decoration.
///
/// IMDb pages differ from TMDB's in every way that matters here: there
/// is no list API, only the page itself, and the page names titles by
/// their IMDb ids (tt...), which the app cannot play. So the import
/// reads the page's title ids, then resolves each one to a TMDB id
/// through TMDB's /find endpoint, on the app's usual TMDB route. A
/// title that does not resolve is skipped, never allowed to sink the
/// rest of the import.
class ImdbListImport {
  const ImdbListImport._();

  /// The list id in [value], or null when it is not an IMDb list
  /// address. The host must be imdb.com itself (a www. in front is the
  /// same site); a lookalike host is not read.
  static String? parseId(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final absolute =
        text.toLowerCase().startsWith('http') ? text : 'https://$text';
    final uri = Uri.tryParse(absolute);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    if (host != 'imdb.com' && host != 'www.imdb.com') {
      return null;
    }
    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length < 2 || segments[0].toLowerCase() != 'list') {
      return null;
    }
    final match = RegExp(r'^(ls\d+)').firstMatch(segments[1].toLowerCase());
    return match?.group(1);
  }

  /// A browser's header set, not just its user agent. IMDb answers a
  /// bare client with a bot wall (403, or a 202 carrying an AWS WAF
  /// JavaScript challenge and no list at all), so the plain request
  /// below wears the full set — and when that still comes back walled,
  /// [fetchPageViaBrowser] is the real-browser fallback.
  static const Map<String, String> browserHeaders = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,'
        'image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://www.imdb.com/',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-User': '?1',
  };

  /// Whether [html] is IMDb's bot wall rather than a list page: the AWS
  /// WAF JavaScript challenge, served with a 202 and no list content.
  /// No header set passes it — only a real browser engine executing the
  /// challenge script does, which is what [fetchPageViaBrowser] is for.
  static bool isChallengePage(String html) =>
      html.contains('token.awswaf.com') ||
      html.contains('awsWafCookieDomainList') ||
      html.contains('challenge.js');

  /// Whether a browser-rendered page counts as the real list page.
  /// The substring check alone lies about solved pages: IMDb's real
  /// page still carries the WAF challenge script tag after the
  /// challenge runs in the browser, so a page rejected on markers
  /// alone would throw away a perfectly good list. Parsed title ids
  /// are the stronger signal — a true challenge page carries none —
  /// so a challenge-marked page that parses to ids is accepted, and
  /// only a challenge-marked page with no ids at all is rejected.
  /// A page without challenge markers is accepted as before, whatever
  /// it parses to; an empty one fails later as an empty list.
  static bool acceptsBrowserPage(String html) {
    if (!isChallengePage(html)) return true;
    final ids = parsePage(html).imdbIds.length;
    if (ids > 0) {
      debugPrint(
        '[ImdbListImport] browser page accepted despite challenge '
        'markers: parsed ids=$ids',
      );
      return true;
    }
    debugPrint(
      '[ImdbListImport] browser page rejected: challenge markers, '
      'no parseable ids',
    );
    return false;
  }

  /// Fetches list [listId] from IMDb, resolves its titles to TMDB ids,
  /// and reads them in the list's own order. [fetchPage] is the page
  /// transport, defaulting to a request with a full browser header set;
  /// [fetchPageViaBrowser] loads a page in a real browser engine and
  /// returns its rendered HTML, used only when the plain request comes
  /// back bot-walled; [resolve] maps one IMDb id to its title,
  /// defaulting to TMDB's /find endpoint. Tests stand in with canned
  /// responses. Throws [TmdbListImportException] for a failed fetch,
  /// or a list with no titles in it once unresolvable entries are
  /// skipped. The debug lines separate the three failures: walled
  /// (fetchFailed), parsed-but-empty (emptyList), and nothing
  /// resolving to TMDB (emptyList after the resolve loop).
  static Future<ImdbListImportResult> fetchList(
    String listId, {
    String proxyUrl = '',
    Future<http.Response> Function(String url)? fetchPage,
    Future<String?> Function(String url)? fetchPageViaBrowser,
    Future<NamedListItem?> Function(String imdbId)? resolve,
  }) async {
    final getPage = fetchPage ??
        (String url) => http.get(
              Uri.parse(url),
              headers: browserHeaders,
            ).timeout(const Duration(seconds: 30));
    final resolveTitle =
        resolve ?? (String imdbId) => resolveImdbId(imdbId, proxyUrl: proxyUrl);

    final seenIds = <String>{};
    final imdbIds = <String>[];
    String? name;
    var url = 'https://www.imdb.com/list/$listId/';
    // A long list pages; follow the next-page link while one is offered,
    // up to ten pages, so a big list does not silently stop at page one.
    var currentPage = 1;
    for (var page = 0; page < 10; page++) {
      final response = await getPage(url);
      String body;
      if (response.statusCode == 200 &&
          !isChallengePage(response.body)) {
        body = response.body;
      } else {
        debugPrint(
          '[ImdbListImport] page $currentPage walled: '
          'status=${response.statusCode} '
          'bytes=${response.body.length} '
          'challenge=${isChallengePage(response.body)}',
        );
        final browserHtml =
            fetchPageViaBrowser == null ? null : await fetchPageViaBrowser(url);
        // The browser path already retried challenge-marked pages
        // inside its own attempt budget; this is the backstop for
        // callers that supply a browser directly. A page that parses
        // to ids is real even with script remnants, so only a
        // challenge-marked page with no ids fails here.
        if (browserHtml == null || !acceptsBrowserPage(browserHtml)) {
          throw const TmdbListImportException(
            TmdbListImportError.fetchFailed,
          );
        }
        debugPrint(
          '[ImdbListImport] page $currentPage read through the browser: '
          'bytes=${browserHtml.length}',
        );
        body = browserHtml;
      }
      final parsed = parsePage(body, currentPage: currentPage);
      debugPrint(
        '[ImdbListImport] page $currentPage parsed: '
        'ids=${parsed.imdbIds.length} '
        'next=${parsed.nextPageUrl != null}',
      );
      name ??= parsed.name;
      for (final id in parsed.imdbIds) {
        if (seenIds.add(id)) imdbIds.add(id);
      }
      final next = parsed.nextPageUrl;
      if (next == null) break;
      final nextPage = _pageNumberOf(next);
      if (nextPage == null || nextPage <= currentPage) break;
      currentPage = nextPage;
      url = next.startsWith('http') ? next : 'https://www.imdb.com$next';
    }
    if (imdbIds.isEmpty) {
      debugPrint('[ImdbListImport] parsed but empty: no ids on any page');
      throw const TmdbListImportException(TmdbListImportError.emptyList);
    }
    final items = <NamedListItem>[];
    for (final imdbId in imdbIds) {
      try {
        final item = await resolveTitle(imdbId);
        if (item != null) items.add(item);
      } catch (_) {
        // One title failing to resolve skips that title, not the list.
      }
    }
    debugPrint(
      '[ImdbListImport] resolved ${items.length} of ${imdbIds.length} ids',
    );
    if (items.isEmpty) {
      debugPrint('[ImdbListImport] zero resolvable: all ids skipped');
      throw const TmdbListImportException(TmdbListImportError.emptyList);
    }
    return ImdbListImportResult(
      name: name != null && name.trim().isNotEmpty
          ? name.trim()
          : 'Imported list',
      items: items,
    );
  }

  /// One IMDb list page, read from its HTML: the list's name, its
  /// titles' IMDb ids in page order, and the next page's link, if the
  /// page offers one past [currentPage]. Pure, so tests feed it canned
  /// pages.
  static ImdbListPage parsePage(String html, {int currentPage = 1}) {
    final name = _pageName(html);
    final nextPageUrl = _nextPageUrl(html, currentPage);
    final fromData = _idsFromNextData(html);
    if (fromData.isNotEmpty) {
      return ImdbListPage(
        name: name,
        imdbIds: fromData,
        nextPageUrl: nextPageUrl,
      );
    }
    final fromLinks = _idsFromTitleLinks(html);
    if (fromLinks.isNotEmpty) {
      return ImdbListPage(
        name: name,
        imdbIds: fromLinks,
        nextPageUrl: nextPageUrl,
      );
    }
    // Last resort for markup drift: every title id in the document, in
    // order. It only runs when both structured reads found nothing, so
    // on a real list page it never outranks them; on a challenge page
    // there are no ids at all, so it stays empty there too.
    return ImdbListPage(
      name: name,
      imdbIds: _idsFromRawScan(html),
      nextPageUrl: nextPageUrl,
    );
  }

  /// The list's name from the page title ("My list - IMDb"), else the
  /// Open Graph title, else nothing (the caller falls back).
  static String? _pageName(String html) {
    final titleMatch =
        RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false)
            .firstMatch(html);
    var name = titleMatch?.group(1)?.trim();
    if (name != null && name.isNotEmpty) {
      name = name.replaceAll(RegExp(r'\s*-\s*IMDb\s*$'), '').trim();
      if (name.isNotEmpty) return _unescape(name);
    }
    final ogMatch = RegExp(
      r'''<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final og = ogMatch?.group(1)?.trim();
    if (og != null && og.isNotEmpty) return _unescape(og);
    return null;
  }

  static String _unescape(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  /// The next page's link, when the page paginates: the smallest page
  /// number above [currentPage], so a "previous" link — or the page's
  /// own link — never loops the import backwards.
  static String? _nextPageUrl(String html, int currentPage) {
    final matches = RegExp(
      r'''href="([^"]*[?&]page=(\d+)[^"]*)"''',
    ).allMatches(html);
    String? bestUrl;
    var bestPage = 0;
    for (final match in matches) {
      final page = int.tryParse(match.group(2) ?? '') ?? 0;
      if (page <= currentPage) continue;
      if (bestUrl == null || page < bestPage) {
        bestUrl = match.group(1);
        bestPage = page;
      }
    }
    return bestUrl == null ? null : _unescape(bestUrl);
  }

  static int? _pageNumberOf(String url) {
    final match = RegExp(r'[?&]page=(\d+)').firstMatch(url);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Title ids from the page's embedded Next.js data. The list itself
  /// is the longest array of id-bearing objects on the page; shorter
  /// arrays are rails and suggestions, and are ignored for that reason.
  /// Falls back to title links when the embedded data is absent.
  static List<String> _idsFromNextData(String html) {
    final scriptMatch = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (scriptMatch == null) return const <String>[];
    Object? decoded;
    try {
      decoded = jsonDecode(scriptMatch.group(1)!);
    } catch (_) {
      return const <String>[];
    }
    var best = const <String>[];
    void visit(Object? node) {
      if (node is List) {
        final ids = <String>[];
        var titled = false;
        for (final entry in node) {
          if (entry is! Map) continue;
          final id = entry['id'];
          if (id is! String || !RegExp(r'^tt\d+$').hasMatch(id)) {
            continue;
          }
          if (entry.containsKey('titleText') ||
              entry.containsKey('title') ||
              entry.containsKey('originalTitleText') ||
              entry.containsKey('name')) {
            titled = true;
          }
          ids.add(id);
        }
        if (titled && ids.length > best.length) {
          best = ids;
        }
        for (final entry in node) {
          visit(entry);
        }
        return;
      }
      if (node is Map) {
        for (final value in node.values) {
          visit(value);
        }
      }
    }

    visit(decoded);
    return _dedupe(best);
  }

  /// Title ids from the page's title links, in page order.
  static List<String> _idsFromTitleLinks(String html) {
    final matches = RegExp(r'/title/(tt\d{7,})/').allMatches(html);
    return _dedupe(matches.map((match) => match.group(1)!).toList());
  }

  /// Every title id anywhere in the document, in order. Only a
  /// last-resort tier: it cannot tell list entries from rails, so it
  /// never runs while the structured tiers find anything.
  static List<String> _idsFromRawScan(String html) {
    final matches = RegExp(r'tt\d{7,}').allMatches(html);
    return _dedupe(matches.map((match) => match.group(0)!).toList());
  }

  static List<String> _dedupe(List<String> ids) {
    final seen = <String>{};
    return ids.where(seen.add).toList(growable: false);
  }

  /// One IMDb id through TMDB's /find endpoint, on the app's usual
  /// TMDB route. Null when the id resolves to nothing the app plays
  /// or the lookup itself fails; the caller skips it either way.
  static Future<NamedListItem?> resolveImdbId(
    String imdbId, {
    String proxyUrl = '',
    Future<http.Response> Function(String url, String proxyUrl)? fetch,
  }) async {
    final send = fetch ??
        (String url, String proxy) => TmdbConnectivity.instance.get(url, proxy);
    final response = await send(
      '$TMDB_API_BASE_URL/find/$imdbId'
      '?api_key=$TMDB_API_KEY&external_source=imdb_id',
      proxyUrl,
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map) return null;
    final movies = body['movie_results'];
    final series = body['tv_results'];
    Map? entry;
    if (movies is List && movies.isNotEmpty && movies.first is Map) {
      entry = movies.first as Map;
    } else if (series is List && series.isNotEmpty && series.first is Map) {
      entry = series.first as Map;
    }
    if (entry == null) return null;
    final isMovie = movies is List && movies.isNotEmpty && movies.first is Map;
    final id = entry['id'];
    if (id is! int) return null;
    final title =
        isMovie ? entry['title'] as String? : entry['name'] as String?;
    if (title == null || title.isEmpty) return null;
    final rating = entry['vote_average'];
    return NamedListItem(
      kind: isMovie ? MediaKind.movie : MediaKind.series,
      tmdbId: id,
      title: title,
      posterPath: entry['poster_path'] as String?,
      backdropPath: entry['backdrop_path'] as String?,
      overview: entry['overview'] as String?,
      releaseDate: (isMovie ? entry['release_date'] : entry['first_air_date'])
          as String?,
      rating: rating is num ? rating.toDouble() : null,
      dateAdded: DateTime.now().toString(),
    );
  }
}

class ImdbListPage {
  const ImdbListPage({
    required this.name,
    required this.imdbIds,
    required this.nextPageUrl,
  });

  final String? name;
  final List<String> imdbIds;
  final String? nextPageUrl;
}

class ImdbListImportResult {
  const ImdbListImportResult({required this.name, required this.items});

  final String name;
  final List<NamedListItem> items;
}
