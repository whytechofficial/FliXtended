import 'package:flixquest/services/imdb_browser_fetch.dart';
import 'package:flutter_test/flutter_test.dart';

const _challengeHtml = '<html><head><title></title></head>'
    '<body>challenge pending</body></html>';

const _listHtml = '<html><head><title>A list - IMDb</title></head><body>'
    '<a href="/title/tt0111161/">A</a></body></html>';

void main() {
  group('ImdbBrowserPageFetcher', () {
    test('returns the page once list content appears', () async {
      var reads = 0;
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async {},
        readHtml: () async {
          reads++;
          return reads < 3 ? _challengeHtml : _listHtml;
        },
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          _listHtml);
      expect(reads, 3);
    });

    test('a failed load reads as nothing', () async {
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async => throw StateError('no browser'),
        readHtml: () async => _listHtml,
      );
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          isNull);
    });

    test('a challenge that never clears times out as nothing', () async {
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async {},
        readHtml: () async => _challengeHtml,
        timeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          isNull);
    });

    test('cancellation stops the wait promptly', () async {
      var cancelled = false;
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async {},
        readHtml: () async {
          cancelled = true;
          return _challengeHtml;
        },
        isCancelled: () => cancelled,
        timeout: const Duration(seconds: 45),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          isNull);
    });

    test('reads failing in a row fail fast instead of timing out',
        () async {
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async {},
        readHtml: () async => throw StateError('browser gone'),
        timeout: const Duration(seconds: 45),
        pollInterval: const Duration(milliseconds: 10),
      );
      final stopwatch = Stopwatch()..start();
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          isNull);
      stopwatch.stop();
      expect(fetcher.browserDied, isTrue);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a failed load counts as a dead browser', () async {
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async => throw StateError('no browser'),
        readHtml: () async => _listHtml,
      );
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          isNull);
      expect(fetcher.browserDied, isTrue);
    });

    test('isolated read failures are tolerated', () async {
      var reads = 0;
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async {},
        readHtml: () async {
          reads++;
          if (reads <= 2) throw StateError('transient');
          return reads == 3 ? _challengeHtml : _listHtml;
        },
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          _listHtml);
      expect(fetcher.browserDied, isFalse);
    });

    test('a timed-out challenge is not a dead browser', () async {
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async {},
        readHtml: () async => _challengeHtml,
        timeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          isNull);
      expect(fetcher.browserDied, isFalse);
    });

    test('cancellation is not a dead browser', () async {
      var cancelled = false;
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async {},
        readHtml: () async {
          cancelled = true;
          return _challengeHtml;
        },
        isCancelled: () => cancelled,
        timeout: const Duration(seconds: 45),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          isNull);
      expect(fetcher.browserDied, isFalse);
    });
  });

  group('ImdbBrowserPageFetcher.fetchWithBrowserRetries', () {
    ImdbBrowserPageFetcher dyingFetcher() => ImdbBrowserPageFetcher(
          load: (_) async {},
          readHtml: () async => throw StateError('browser gone'),
          pollInterval: const Duration(milliseconds: 10),
        );

    ImdbBrowserPageFetcher listingFetcher() => ImdbBrowserPageFetcher(
          load: (_) async {},
          readHtml: () async => _listHtml,
          pollInterval: const Duration(milliseconds: 10),
        );

    test('a browser that dies is replaced and the import succeeds',
        () async {
      var created = 0;
      final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
        'https://www.imdb.com/list/ls1/',
        createFetcher: () {
          created++;
          return created == 1 ? dyingFetcher() : listingFetcher();
        },
      );
      expect(html, _listHtml);
      expect(created, 2);
    });

    test('three dead browsers exhaust the retries', () async {
      var created = 0;
      final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
        'https://www.imdb.com/list/ls1/',
        createFetcher: () {
          created++;
          return dyingFetcher();
        },
      );
      expect(html, isNull);
      expect(created, 3);
    });

    test('maxAttempts bounds the retries', () async {
      var created = 0;
      final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
        'https://www.imdb.com/list/ls1/',
        createFetcher: () {
          created++;
          return dyingFetcher();
        },
        maxAttempts: 2,
      );
      expect(html, isNull);
      expect(created, 2);
    });

    test('a timed-out challenge is retried with a fresh browser',
        () async {
      var created = 0;
      final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
        'https://www.imdb.com/list/ls1/',
        createFetcher: () {
          created++;
          if (created == 1) {
            return ImdbBrowserPageFetcher(
              load: (_) async {},
              readHtml: () async => _challengeHtml,
              timeout: const Duration(milliseconds: 50),
              pollInterval: const Duration(milliseconds: 10),
            );
          }
          return listingFetcher();
        },
      );
      expect(html, _listHtml);
      expect(created, 2);
    });

    test('a timed-out pass reports timedOut, not browserDied', () async {
      final fetcher = ImdbBrowserPageFetcher(
        load: (_) async {},
        readHtml: () async => _challengeHtml,
        timeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(await fetcher.fetchPage('https://www.imdb.com/list/ls1/'),
          isNull);
      expect(fetcher.timedOut, isTrue);
      expect(fetcher.browserDied, isFalse);
    });

    test('all timed-out attempts exhaust the retries', () async {
      var created = 0;
      final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
        'https://www.imdb.com/list/ls1/',
        createFetcher: () {
          created++;
          return ImdbBrowserPageFetcher(
            load: (_) async {},
            readHtml: () async => _challengeHtml,
            timeout: const Duration(milliseconds: 50),
            pollInterval: const Duration(milliseconds: 10),
          );
        },
      );
      expect(html, isNull);
      expect(created, 3);
    });

    test('a page the acceptance check rejects is retried with a fresh browser',
        () async {
      var created = 0;
      var checked = 0;
      final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
        'https://www.imdb.com/list/ls1/',
        createFetcher: () {
          created++;
          return listingFetcher();
        },
        acceptPage: (_) {
          checked++;
          return checked > 1;
        },
      );
      expect(html, _listHtml);
      expect(created, 2);
      expect(checked, 2);
    });

    test('pages rejected by every attempt exhaust the retries', () async {
      var created = 0;
      final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
        'https://www.imdb.com/list/ls1/',
        createFetcher: () {
          created++;
          return listingFetcher();
        },
        acceptPage: (_) => false,
      );
      expect(html, isNull);
      expect(created, 3);
    });

    test('a failed load is retried with a fresh browser', () async {
      var created = 0;
      final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
        'https://www.imdb.com/list/ls1/',
        createFetcher: () {
          created++;
          if (created == 1) {
            return ImdbBrowserPageFetcher(
              load: (_) async => throw StateError('no browser'),
              readHtml: () async => _listHtml,
            );
          }
          return listingFetcher();
        },
      );
      expect(html, _listHtml);
      expect(created, 2);
    });

    test('cancellation before the first attempt creates no browser',
        () async {
      var created = 0;
      final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
        'https://www.imdb.com/list/ls1/',
        createFetcher: () {
          created++;
          return listingFetcher();
        },
        isCancelled: () => true,
      );
      expect(html, isNull);
      expect(created, 0);
    });
  });
}
