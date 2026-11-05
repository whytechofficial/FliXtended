import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flixquest/catalog/media_item.dart';
import 'package:flixquest/controllers/named_lists_controller.dart';
import 'package:flixquest/models/named_list.dart';
import 'package:flixquest/provider/named_lists_provider.dart';
import 'package:flixquest/services/imdb_list_import.dart';
import 'package:flixquest/services/tmdb_list_import.dart';

/// An in-memory stand-in for the database, so the provider's behaviour
/// is tested without a device.
class FakeNamedListsStore implements NamedListsStore {
  final _lists = <String, NamedList>{};
  var _nextId = 0;

  @override
  Future<List<NamedList>> getLists() async => _lists.values.toList();

  @override
  Future<NamedList> insertList(String name, {String description = ''}) async {
    final list = NamedList(
      id: 'list-${_nextId++}',
      name: name,
      description: description,
      createdAt: DateTime.now().toString(),
    );
    _lists[list.id] = list;
    return list;
  }

  @override
  Future<void> renameList(String id, String name) async {
    final list = _lists[id];
    if (list != null) _lists[id] = list.copyWith(name: name);
  }

  @override
  Future<void> updateListDetails(
    String id,
    String name,
    String description,
  ) async {
    final list = _lists[id];
    if (list != null) {
      _lists[id] = list.copyWith(name: name, description: description);
    }
  }

  @override
  Future<void> deleteList(String id) async {
    _lists.remove(id);
  }

  @override
  Future<void> insertItem(String listId, NamedListItem item) async {
    final list = _lists[listId];
    if (list == null) return;
    if (list.items.any(
      (entry) => entry.kind == item.kind && entry.tmdbId == item.tmdbId,
    )) {
      return;
    }
    _lists[listId] = list.copyWith(items: [...list.items, item]);
  }

  @override
  Future<void> deleteItem(String listId, MediaKind kind, int tmdbId) async {
    final list = _lists[listId];
    if (list == null) return;
    _lists[listId] = list.copyWith(
      items: list.items
          .where(
            (entry) => !(entry.kind == kind && entry.tmdbId == tmdbId),
          )
          .toList(),
    );
  }

  @override
  Future<void> insertFullList(NamedList list) async {
    _lists[list.id] = list;
  }

  @override
  Future<void> updateListRow(
    String id,
    String name,
    String updatedAt,
    String description,
  ) async {
    final list = _lists[id];
    if (list != null) {
      _lists[id] = list.copyWith(
        name: name,
        description: description,
        updatedAt: updatedAt,
      );
    }
  }
}

MediaItem _movie(int id) => MediaItem(
      kind: MediaKind.movie,
      id: id,
      title: 'Film $id',
      overview: '',
      posterPath: '/p$id.jpg',
      backdropPath: null,
      rating: 8.0,
      releaseDate: '2020-01-01',
    );

void main() {
  // The TMDB key is read from dotenv; tests stand in with a dummy value.
  setUpAll(() {
    dotenv.testLoad(fileInput: 'TMDB_API_KEY=test-key');
  });

  group('named lists', () {
    test('a blank name creates nothing', () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      expect(await provider.createList('   '), isNull);
      expect(provider.lists, isEmpty);
    });

    test('create, rename and delete', () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      final list = await provider.createList('  Rainy day  ');
      expect(list!.name, 'Rainy day');
      expect(provider.lists, hasLength(1));

      await provider.renameList(list.id, '  Family night ');
      expect(provider.lists.single.name, 'Family night');
      await provider.renameList(list.id, '   ');
      expect(provider.lists.single.name, 'Family night');

      await provider.deleteList(list.id);
      expect(provider.lists, isEmpty);
    });

    test('adding twice keeps one entry; removing drops it', () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      final list = await provider.createList('Watchlist') as NamedList;

      await provider.addToList(list.id, _movie(550));
      await provider.addToList(list.id, _movie(550));
      expect(provider.lists.single.items, hasLength(1));
      expect(provider.listsContaining(_movie(550)), hasLength(1));

      await provider.removeFromList(list.id, MediaKind.movie, 550);
      expect(provider.lists.single.items, isEmpty);
      expect(provider.listsContaining(_movie(550)), isEmpty);
    });

    test('deleting a list drops its entries', () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      final list = await provider.createList('To watch') as NamedList;
      await provider.addToList(list.id, _movie(550));
      await provider.deleteList(list.id);
      expect(provider.lists, isEmpty);
    });
  });

  group('TMDB list links', () {
    test('a list id reads with or without a slug or scheme', () {
      expect(
        TmdbListImport.parseId(
          'https://www.themoviedb.org/list/12345-my-favourites',
        ),
        12345,
      );
      expect(
        TmdbListImport.parseId('https://themoviedb.org/list/12345'),
        12345,
      );
      expect(
        TmdbListImport.parseId('themoviedb.org/list/12345-summer'),
        12345,
      );
    });

    test('anything that is not a TMDB list address reads as nothing', () {
      expect(TmdbListImport.parseId(''), isNull);
      expect(
          TmdbListImport.parseId('https://themoviedb.org/movie/550'), isNull);
      expect(TmdbListImport.parseId('https://themoviedb.org/list/'), isNull);
      expect(TmdbListImport.parseId('https://themoviedb.org/list/abc'), isNull);
      expect(
        TmdbListImport.parseId('https://themoviedb.org.evil.com/list/123'),
        isNull,
      );
      expect(
        TmdbListImport.parseId('https://example.com/list/123'),
        isNull,
      );
    });

    test('a list response reads films and series, skipping people', () {
      final items = TmdbListImport.itemsFromJson([
        {
          'media_type': 'movie',
          'id': 550,
          'title': 'Fight Club',
          'poster_path': '/p.jpg',
          'release_date': '1999-10-15',
          'vote_average': 8.4,
        },
        {
          'media_type': 'tv',
          'id': 1396,
          'name': 'Breaking Bad',
          'first_air_date': '2008-01-20',
        },
        {'media_type': 'person', 'id': 819, 'name': 'Edward Norton'},
        {'media_type': 'movie', 'title': 'No id at all'},
        {'media_type': 'movie', 'id': 999},
      ]);
      expect(items, hasLength(2));
      expect(items[0].kind, MediaKind.movie);
      expect(items[0].tmdbId, 550);
      expect(items[0].rating, 8.4);
      expect(items[1].kind, MediaKind.series);
      expect(items[1].title, 'Breaking Bad');
      expect(items[1].rating, isNull);
    });

    test('import creates a list named after the TMDB list', () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      final list = await provider.importFromTmdb(
        'https://www.themoviedb.org/list/12345-staff-picks',
        fetch: (url, _) async {
          expect(url, contains('/list/12345?'));
          return http.Response(
            jsonEncode({
              'name': 'Staff picks',
              'items': [
                {'media_type': 'movie', 'id': 550, 'title': 'Fight Club'},
                {'media_type': 'movie', 'id': 550, 'title': 'Fight Club'},
              ],
            }),
            200,
          );
        },
      );
      expect(list.name, 'Staff picks');
      expect(provider.lists.single.items, hasLength(1));
    });

    test('import fails cleanly for a bad link, a failed fetch, an empty list',
        () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      await expectLater(
        provider.importFromTmdb('https://example.com/list/1'),
        throwsA(
          isA<TmdbListImportException>().having(
            (e) => e.error,
            'error',
            TmdbListImportError.invalidLink,
          ),
        ),
      );
      await expectLater(
        provider.importFromTmdb('https://themoviedb.org/list/1',
            fetch: (_, __) async => http.Response('Not found', 404)),
        throwsA(
          isA<TmdbListImportException>().having(
            (e) => e.error,
            'error',
            TmdbListImportError.fetchFailed,
          ),
        ),
      );
      await expectLater(
        provider.importFromTmdb('https://themoviedb.org/list/1',
            fetch: (_, __) async =>
                http.Response(jsonEncode({'name': 'Empty', 'items': []}), 200)),
        throwsA(
          isA<TmdbListImportException>().having(
            (e) => e.error,
            'error',
            TmdbListImportError.emptyList,
          ),
        ),
      );
      expect(provider.lists, isEmpty);
    });
  });

  group('list descriptions', () {
    test('a description survives create, edit and the map', () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      final list = await provider.createList(
        'Rainy day',
        description: 'For grey Sundays',
      ) as NamedList;
      expect(list.description, 'For grey Sundays');
      await provider.updateListDetails(
        list.id,
        'Rainy day',
        'For storms too',
      );
      expect(provider.lists.single.description, 'For storms too');
      final restored = NamedList.fromMap(provider.lists.single.toMap());
      expect(restored.description, 'For storms too');
    });

    test('a map without a description reads as empty', () {
      final restored = NamedList.fromMap(<String, Object?>{
        'id': 'a',
        'name': 'List',
        'created_at': '2026-11-01',
        'updated_at': '2026-11-02',
      });
      expect(restored.description, isEmpty);
    });
  });

  group('IMDb list links', () {
    test('a list id reads with or without a slug or scheme', () {
      expect(
        ImdbListImport.parseId('https://www.imdb.com/list/ls123456789/'),
        'ls123456789',
      );
      expect(
        ImdbListImport.parseId('imdb.com/list/ls123456789-my-list'),
        'ls123456789',
      );
      expect(
        ImdbListImport.parseId(
          'https://imdb.com/list/ls123456789?ref_=ls',
        ),
        'ls123456789',
      );
    });

    test('anything that is not an IMDb list address reads as nothing', () {
      expect(ImdbListImport.parseId(''), isNull);
      expect(
        ImdbListImport.parseId('https://www.imdb.com/title/tt0111161/'),
        isNull,
      );
      expect(ImdbListImport.parseId('https://www.imdb.com/list/'), isNull);
      expect(
        ImdbListImport.parseId('https://www.imdb.com.evil.com/list/ls123'),
        isNull,
      );
      expect(
        ImdbListImport.parseId('https://www.themoviedb.org/list/12345'),
        isNull,
      );
    });

    test('a page reads its name and ids from embedded data, longest wins', () {
      final page = ImdbListImport.parsePage(
        '<html><head><title>My favourites - IMDb</title></head><body>'
        '<script id="__NEXT_DATA__" type="application/json">'
        '${jsonEncode({
              'props': {
                'pageProps': {
                  'rail': {
                    'items': [
                      {
                        'id': 'tt9999999',
                        'titleText': {'text': 'Decoy'}
                      },
                    ],
                  },
                  'mainColumnData': {
                    'list': {
                      'items': [
                        {
                          'id': 'tt0111161',
                          'titleText': {'text': 'The Shawshank Redemption'},
                        },
                        {
                          'id': 'tt0068646',
                          'titleText': {'text': 'The Godfather'}
                        },
                        {
                          'id': 'tt0111161',
                          'titleText': {'text': 'The Shawshank Redemption'},
                        },
                      ],
                    },
                  },
                },
              },
            })}'
        '</script></body></html>',
      );
      expect(page.name, 'My favourites');
      expect(page.imdbIds, ['tt0111161', 'tt0068646']);
      expect(page.nextPageUrl, isNull);
    });

    test('a page without embedded data falls back to title links', () {
      final page = ImdbListImport.parsePage(
        '<html><head><title>Old style - IMDb</title></head><body>'
        '<a href="/title/tt0133093/">The Matrix</a>'
        '<a href="/title/tt0133093/">The Matrix</a>'
        '<a href="/title/tt0234215/">The Matrix Reloaded</a>'
        '</body></html>',
      );
      expect(page.imdbIds, ['tt0133093', 'tt0234215']);
    });

    test('a page offers its next page, never its own or a previous one', () {
      final page = ImdbListImport.parsePage(
        '<html><body>'
        '<a href="/list/ls1/?page=1">1</a>'
        '<a href="/list/ls1/?page=2">2</a>'
        '<a href="/list/ls1/?page=3">3</a>'
        '</body></html>',
        currentPage: 2,
      );
      expect(page.nextPageUrl, contains('page=3'));
    });

    test('a /find response maps a film and a series; nothing maps to null',
        () async {
      final film = await ImdbListImport.resolveImdbId(
        'tt0111161',
        fetch: (url, _) async {
          expect(url, contains('/find/tt0111161?'));
          expect(url, contains('external_source=imdb_id'));
          return http.Response(
            jsonEncode({
              'movie_results': [
                {
                  'id': 278,
                  'title': 'The Shawshank Redemption',
                  'vote_average': 8.7,
                },
              ],
              'tv_results': [],
            }),
            200,
          );
        },
      );
      expect(film!.kind, MediaKind.movie);
      expect(film.tmdbId, 278);
      expect(film.rating, 8.7);

      final series = await ImdbListImport.resolveImdbId(
        'tt0903747',
        fetch: (_, __) async => http.Response(
          jsonEncode({
            'movie_results': [],
            'tv_results': [
              {
                'id': 1396,
                'name': 'Breaking Bad',
                'first_air_date': '2008-01-20',
              },
            ],
          }),
          200,
        ),
      );
      expect(series!.kind, MediaKind.series);
      expect(series.tmdbId, 1396);

      final nothing = await ImdbListImport.resolveImdbId(
        'tt0000000',
        fetch: (_, __) async => http.Response(
          jsonEncode({'movie_results': [], 'tv_results': []}),
          200,
        ),
      );
      expect(nothing, isNull);
    });

    test('import skips unresolvable titles and keeps the rest, in order',
        () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      final list = await provider.importFromImdb(
        'https://www.imdb.com/list/ls123456789/',
        fetchPage: (_) async => http.Response(
          '<html><head><title>Mixed - IMDb</title></head><body>'
          '<a href="/title/tt0111161/">A</a>'
          '<a href="/title/tt0000000/">B</a>'
          '<a href="/title/tt0068646/">C</a>'
          '</body></html>',
          200,
        ),
        resolve: (imdbId) async {
          if (imdbId == 'tt0000000') return null;
          return NamedListItem(
            kind: MediaKind.movie,
            tmdbId: imdbId == 'tt0111161' ? 278 : 238,
            title: imdbId,
            dateAdded: '2026-11-02',
          );
        },
      );
      expect(list.name, 'Mixed');
      expect(
        provider.lists.single.items.map((item) => item.tmdbId),
        [278, 238],
      );
    });

    test('the bot-wall challenge page reads as walled, with no ids', () {
      const challenge = '<html><head><title></title>'
          '<script>window.awsWafCookieDomainList = ["imdb.com"];</script>'
          '<script src="https://example.token.awswaf.com/x/challenge.js">'
          '</script></head><body></body></html>';
      expect(ImdbListImport.isChallengePage(challenge), isTrue);
      expect(ImdbListImport.parsePage(challenge).imdbIds, isEmpty);
      expect(ImdbListImport.acceptsBrowserPage(challenge), isFalse);
    });

    test('a challenge-marked page that parses to ids counts as real', () {
      const solved = '<html><head><title>Solved - IMDb</title>'
          '<script src="https://example.token.awswaf.com/x/challenge.js">'
          '</script></head><body>'
          '<a href="/title/tt0111161/">A</a>'
          '</body></html>';
      expect(ImdbListImport.isChallengePage(solved), isTrue);
      expect(ImdbListImport.acceptsBrowserPage(solved), isTrue);
    });

    test('a browser page carrying challenge markers but real ids imports',
        () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      final list = await provider.importFromImdb(
        'https://www.imdb.com/list/ls123456789/',
        fetchPage: (_) async => http.Response('<html></html>', 202),
        fetchPageViaBrowser: (_) async =>
            '<html><head><title>Solved - IMDb</title>'
            '<script src="https://example.token.awswaf.com/x/challenge.js">'
            '</script></head><body>'
            '<a href="/title/tt0111161/">A</a>'
            '</body></html>',
        resolve: (imdbId) async => NamedListItem(
          kind: MediaKind.movie,
          tmdbId: 278,
          title: imdbId,
          dateAdded: '2026-11-02',
        ),
      );
      expect(list.name, 'Solved');
      expect(provider.lists.single.items.map((item) => item.tmdbId), [278]);
    });

    test('a page with ids in neither data nor links falls back to a raw scan',
        () {
      final page = ImdbListImport.parsePage(
        '<html><head><title>Drifted - IMDb</title></head><body>'
        '<script>var data = {"items":[{"imdb":"tt0111161"},'
        '{"imdb":"tt0068646"},{"imdb":"tt0111161"}]};</script>'
        '</body></html>',
      );
      expect(page.imdbIds, ['tt0111161', 'tt0068646']);
    });

    test('the plain request wears a browser header set', () {
      final headers = ImdbListImport.browserHeaders;
      expect(headers['User-Agent'], contains('Chrome/126'));
      expect(headers['Accept'], contains('text/html'));
      expect(headers['Referer'], 'https://www.imdb.com/');
      expect(headers['Sec-Fetch-Dest'], 'document');
    });

    test('a walled plain request falls back to the browser page', () async {
      const challenge = '<html><head><title></title>'
          '<script>window.awsWafCookieDomainList = ["imdb.com"];</script>'
          '</head><body></body></html>';
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      var browserUsed = false;
      final list = await provider.importFromImdb(
        'https://www.imdb.com/list/ls123456789/',
        fetchPage: (_) async => http.Response(challenge, 202),
        fetchPageViaBrowser: (url) async {
          browserUsed = true;
          expect(url, contains('ls123456789'));
          return '<html><head><title>Via browser - IMDb</title></head><body>'
              '<a href="/title/tt0111161/">A</a>'
              '<a href="/title/tt0068646/">C</a>'
              '</body></html>';
        },
        resolve: (imdbId) async => NamedListItem(
          kind: MediaKind.movie,
          tmdbId: imdbId == 'tt0111161' ? 278 : 238,
          title: imdbId,
          dateAdded: '2026-11-02',
        ),
      );
      expect(browserUsed, isTrue);
      expect(list.name, 'Via browser');
      expect(
        provider.lists.single.items.map((item) => item.tmdbId),
        [278, 238],
      );
    });

    test('a plain request that succeeds never touches the browser',
        () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      final list = await provider.importFromImdb(
        'https://www.imdb.com/list/ls123456789/',
        fetchPage: (_) async => http.Response(
          '<html><head><title>Plain page - IMDb</title></head><body>'
          '<a href="/title/tt0111161/">A</a>'
          '</body></html>',
          200,
        ),
        fetchPageViaBrowser: (_) async =>
            throw StateError('browser must not be called'),
        resolve: (imdbId) async => NamedListItem(
          kind: MediaKind.movie,
          tmdbId: 278,
          title: imdbId,
          dateAdded: '2026-11-02',
        ),
      );
      expect(list.name, 'Plain page');
      expect(provider.lists.single.items.map((item) => item.tmdbId), [278]);
    });

    test('a walled plain request without a browser fails as fetchFailed',
        () async {
      await expectLater(
        ImdbListImport.fetchList(
          'ls123456789',
          fetchPage: (_) async => http.Response('<html></html>', 403),
          resolve: (_) async => null,
        ),
        throwsA(
          isA<TmdbListImportException>().having(
            (error) => error.error,
            'error',
            TmdbListImportError.fetchFailed,
          ),
        ),
      );
    });

    test('a browser page that is still walled fails as fetchFailed', () async {
      await expectLater(
        ImdbListImport.fetchList(
          'ls123456789',
          fetchPage: (_) async => http.Response('<html></html>', 202),
          fetchPageViaBrowser: (_) async =>
              '<script src="https://example.token.awswaf.com/x/challenge.js">'
              '</script>',
          resolve: (_) async => null,
        ),
        throwsA(
          isA<TmdbListImportException>().having(
            (error) => error.error,
            'error',
            TmdbListImportError.fetchFailed,
          ),
        ),
      );
    });

    test('importFromLink routes TMDB and IMDb links, rejects the rest',
        () async {
      final provider = NamedListsProvider(store: FakeNamedListsStore());
      await provider.fetchLists();
      final viaTmdb = await provider.importFromLink(
        'https://www.themoviedb.org/list/12345-x',
        fetch: (_, __) async => http.Response(
          jsonEncode({
            'name': 'TMDB one',
            'items': [
              {'media_type': 'movie', 'id': 550, 'title': 'Fight Club'},
            ],
          }),
          200,
        ),
      );
      expect(viaTmdb.name, 'TMDB one');
      await expectLater(
        provider.importFromLink('https://example.com/list/1'),
        throwsA(isA<TmdbListImportException>()),
      );
    });
  });
}
