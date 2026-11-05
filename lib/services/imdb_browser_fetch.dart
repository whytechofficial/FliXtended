import 'package:flutter/foundation.dart';

/// Loads IMDb list pages in a real browser engine and returns the
/// rendered page HTML. A plain HTTP request cannot pass IMDb's AWS WAF
/// JavaScript challenge, so this is the fallback the import uses when
/// the plain request comes back bot-walled.
///
/// [load] navigates the browser to [url]; [readHtml] returns the page's
/// current outer HTML; [isCancelled] reports the caller going away, so
/// a backed-out import stops promptly instead of polling to timeout.
/// All three are injected so tests can stand in a fake browser; the
/// import screen wires them to a WebView. No account, no login: the
/// list page itself is public, and the browser only renders it.
typedef ImdbBrowserLoad = Future<void> Function(String url);
typedef ImdbBrowserReadHtml = Future<String?> Function();

/// Whether a marker-bearing page counts as the real list page. The
/// caller supplies it when a rendered page can carry leftovers that
/// look like a bot wall — IMDb's solved challenge leaves its script
/// tag in the DOM — so a page is rejected only when it carries those
/// markers and nothing parseable. Null means every marker-bearing
/// page counts, which is the previous behavior.
typedef ImdbBrowserAcceptPage = bool Function(String html);

class ImdbBrowserPageFetcher {
  ImdbBrowserPageFetcher({
    required this.load,
    required this.readHtml,
    this.isCancelled,
    this.timeout = const Duration(seconds: 45),
    this.pollInterval = const Duration(seconds: 1),
    this.consecutiveFailureLimit = 3,
  });

  final ImdbBrowserLoad load;
  final ImdbBrowserReadHtml readHtml;
  final bool Function()? isCancelled;
  final Duration timeout;
  final Duration pollInterval;

  /// How many reads in a row may fail before the browser is declared
  /// dead. One failed read is transient noise and is tolerated; reads
  /// failing one after another mean the browser process went away, and
  /// waiting out the timeout after that only wastes the user's time.
  final int consecutiveFailureLimit;

  /// True when the most recent [fetchPage] pass ended because the
  /// browser itself went away — its reads failing in a row, or its
  /// load failing — as opposed to timing out with a live browser or
  /// being cancelled.
  bool browserDied = false;

  /// True when the most recent [fetchPage] pass ran out its timeout
  /// with a live browser: the challenge never cleared, or the page's
  /// client-side content never appeared. A timed-out pass is still
  /// worth retrying with a fresh browser — a second load often clears
  /// faster (challenge cookies and cached scripts carry over) — but
  /// it is a different outcome from a death, so the retry log tells
  /// the two apart.
  bool timedOut = false;

  /// The page's HTML once it actually carries list content, else null:
  /// the challenge never cleared, the load failed, the browser died,
  /// or the caller left. A challenge page carries neither embedded
  /// data nor title links, so polling for either marker is polling
  /// for the challenge having passed.
  Future<String?> fetchPage(String url) async {
    browserDied = false;
    timedOut = false;
    try {
      await load(url);
    } catch (_) {
      browserDied = true;
      return null;
    }
    var consecutiveFailures = 0;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) return null;
      String? html;
      try {
        html = await readHtml();
      } catch (_) {
        html = null;
        consecutiveFailures++;
        if (consecutiveFailures >= consecutiveFailureLimit) {
          browserDied = true;
          debugPrint(
            '[ImdbBrowserPageFetcher] browser died: '
            '$consecutiveFailures consecutive read failures',
          );
          return null;
        }
      }
      if (html != null) {
        consecutiveFailures = 0;
        if (html.contains('__NEXT_DATA__') || html.contains('/title/tt')) {
          return html;
        }
      }
      await Future.delayed(pollInterval);
    }
    // Past the deadline with a live browser and no list markers: the
    // challenge never cleared, or slow client-side content never
    // appeared. Distinct from a death, and retryable, so say so.
    timedOut = true;
    debugPrint('[ImdbBrowserPageFetcher] browser pass timed out');
    return null;
  }

  /// One page read across fresh browsers. Each attempt gets its own
  /// browser from [createFetcher], because a dead browser cannot be
  /// revived — the caller wires each new browser to its own engine
  /// (the import screen builds a new WebView per attempt). A pass
  /// that dies is retried with a new browser, and so is a pass that
  /// times out with a live browser: slow client-side pages may simply
  /// need a second load, and a fresh load often clears faster
  /// (challenge cookies and cached scripts carry over). A pass whose
  /// page [acceptPage] rejects is retried the same way. At most
  /// [maxAttempts] browsers per call, deaths, timeouts, and
  /// rejections combined, so the worst case stays bounded; a
  /// cancelled wait stops everything at once. Returns the first page
  /// HTML carrying list content that [acceptPage] accepts, else null.
  /// Each attempt's outcome is logged, so an on-device log shows
  /// whether a failure was a death, a timeout, a rejection, or a
  /// cancellation.
  static Future<String?> fetchWithBrowserRetries(
    String url, {
    required ImdbBrowserPageFetcher Function() createFetcher,
    int maxAttempts = 3,
    bool Function()? isCancelled,
    ImdbBrowserAcceptPage? acceptPage,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (isCancelled?.call() ?? false) return null;
      final fetcher = createFetcher();
      final html = await fetcher.fetchPage(url);
      if (html != null && (acceptPage == null || acceptPage(html))) {
        debugPrint(
          '[ImdbBrowserPageFetcher] browser attempt ${attempt + 1}: '
          'success',
        );
        return html;
      }
      if (html != null) {
        debugPrint(
          '[ImdbBrowserPageFetcher] browser attempt ${attempt + 1}: '
          'page rejected; retrying',
        );
        continue;
      }
      if (isCancelled?.call() ?? false) return null;
      if (fetcher.browserDied) {
        debugPrint(
          '[ImdbBrowserPageFetcher] browser attempt ${attempt + 1}: '
          'died; retrying',
        );
      } else if (fetcher.timedOut) {
        debugPrint(
          '[ImdbBrowserPageFetcher] browser attempt ${attempt + 1}: '
          'timed out with a live browser; retrying',
        );
      } else {
        // Cancelled inside the pass itself; the wait is over.
        return null;
      }
    }
    debugPrint(
      '[ImdbBrowserPageFetcher] browser attempts exhausted '
      '($maxAttempts attempts)',
    );
    return null;
  }
}
