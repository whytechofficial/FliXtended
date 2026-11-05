import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/named_list.dart';
import '../../provider/named_lists_provider.dart';
import '../../services/imdb_browser_fetch.dart';
import '../../services/imdb_list_import.dart';
import '../../services/tmdb_list_import.dart';

/// What an IMDb import screen pops with: the created list, or the
/// import error the caller already knows how to report. Null when the
/// user backs out before the import finishes.
typedef ImdbImportResult = ({NamedList? list, TmdbListImportException? error});

/// The import stage shown on the spinner, so a slow import never
/// looks stuck: checking the link, solving IMDb's check in a browser,
/// then resolving the titles the list names.
enum ImdbImportStage { checking, solvingBrowser, resolving }

/// The translation key for [stage]'s spinner text.
String imdbImportStageKey(ImdbImportStage stage) => switch (stage) {
      ImdbImportStage.checking => 'import_imdb_checking',
      ImdbImportStage.solvingBrowser => 'import_imdb_solving',
      ImdbImportStage.resolving => 'import_imdb_resolving',
    };

/// Imports one public IMDb list link. IMDb bot-walls plain requests —
/// a 403, or a 202 carrying an AWS WAF JavaScript challenge — so the
/// import runs with a real browser engine behind it: the page loads in
/// a WebView, the challenge script runs there as it would in the
/// user's browser, and the rendered list page is what gets parsed.
/// Nothing is signed in to, and no list data leaves the device
/// except the public TMDB lookups that resolve each title.
///
/// The browser fills the screen behind a spinner overlay: IMDb list
/// pages render their content client-side, and virtualized lists only
/// render items for a real viewport — a pixel-sized browser could
/// time out forever on a slow page with nothing ever appearing. A
/// browser pass that dies, that times out with a live browser, or
/// whose page is still challenge-marked with nothing parseable in
/// it, is retried with a fresh WebView, up to three browser attempts
/// per tap, instead of failing the whole import. A page that parses
/// to title ids counts as real even when it still carries the
/// challenge script tag — a solved challenge leaves that tag in the
/// DOM, while a true challenge page carries no ids at all. Backing
/// out abandons the import; the browser pass stops promptly, though
/// a resolve already in flight may still land its list — the same
/// list the import was asked for.
class ImdbImportScreen extends StatefulWidget {
  const ImdbImportScreen({super.key, required this.link});

  final String link;

  @override
  State<ImdbImportScreen> createState() => _ImdbImportScreenState();
}

class _ImdbImportScreenState extends State<ImdbImportScreen> {
  late WebViewController _controller;
  var _stage = ImdbImportStage.checking;
  var _browserAttempt = 0;
  bool _started = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final provider = context.read<NamedListsProvider>();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _runImport(provider),
    );
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  /// The browser fallback for one page: up to three fresh browsers,
  /// because a dead browser cannot be revived and a timed-out load
  /// may clear faster on a second try. Each attempt builds its own
  /// WebView — the widget below is keyed by attempt, so a new
  /// controller always gets a new platform view — and the spinner
  /// text follows the stage, so waiting never looks stuck.
  Future<String?> _fetchPageViaBrowser(String url) async {
    final html = await ImdbBrowserPageFetcher.fetchWithBrowserRetries(
      url,
      acceptPage: ImdbListImport.acceptsBrowserPage,
      createFetcher: () {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted);
        final fetcher = ImdbBrowserPageFetcher(
          load: (target) => controller.loadRequest(Uri.parse(target)),
          readHtml: () async {
            final raw = await controller.runJavaScriptReturningResult(
              'JSON.stringify(document.documentElement.outerHTML)',
            );
            if (raw is! String) return null;
            final decoded = jsonDecode(raw);
            return decoded is String ? decoded : null;
          },
          isCancelled: () => _cancelled,
        );
        _controller = controller;
        _browserAttempt++;
        if (mounted) {
          setState(() => _stage = ImdbImportStage.solvingBrowser);
        }
        return fetcher;
      },
      isCancelled: () => _cancelled,
    );
    if (html != null && mounted) {
      setState(() => _stage = ImdbImportStage.resolving);
    }
    return html;
  }

  Future<void> _runImport(NamedListsProvider provider) async {
    try {
      final list = await provider.importFromImdb(
        widget.link,
        fetchPageViaBrowser: _fetchPageViaBrowser,
      );
      if (!mounted) return;
      Navigator.of(context).pop<ImdbImportResult>((list: list, error: null));
    } on TmdbListImportException catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop<ImdbImportResult>((list: null, error: error));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop<ImdbImportResult>(
        (
          list: null,
          error: const TmdbListImportException(
            TmdbListImportError.fetchFailed,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('import_tmdb_list'))),
      body: Stack(
        children: [
          // Full-size browser: client-rendered lists only render
          // their items for a real viewport, so the engine fills the
          // screen instead of living in a 1x1 box. It sits behind the
          // spinner overlay — it is the rendering engine, not
          // something to watch — but it is genuinely laid out, which
          // is what makes virtualized content appear at all.
          Positioned.fill(
            child: WebViewWidget(
              key: ValueKey(_browserAttempt),
              controller: _controller,
            ),
          ),
          Container(
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: 0.85),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(tr(imdbImportStageKey(_stage))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
