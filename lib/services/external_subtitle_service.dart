import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:better_player_plus/better_player_plus.dart';
import '../functions/function.dart';
import '../models/external_subtitles.dart';
import '../video_providers/scraper_api.dart';
import 'opensubtitles_service.dart';

/// Fetches external subtitles through the FlixQuest Scraper API.
///
/// Search and file download both go through the scraper: it holds the provider
/// credentials, normalizes every file to UTF-8 and strips aggregator ads, so
/// the app never talks to a subtitle source directly.
///
/// When the scraper API fails or returns nothing (its subtitle upstream is
/// currently down), the search transparently falls back to the key-free
/// OpenSubtitles REST API, keeping the rest of the flow identical.
class ExternalSubtitleService {
  ExternalSubtitleService(this.scraperApiUrl);

  final String scraperApiUrl;

  /// Fetch external subtitles for a movie using TMDB ID
  Future<List<ExternalSubtitle>> fetchMovieSubtitles(int tmdbId) async {
    try {
      final fromScraper =
          await ScraperApi(scraperApiUrl).searchSubtitles(tmdbId: tmdbId);
      if (fromScraper.isNotEmpty) return fromScraper;
    } catch (_) {
      // Fall through to the OpenSubtitles fallback below.
    }
    final imdbId = await const OpenSubtitlesService()
        .fetchImdbId(tmdbId: tmdbId, isMovie: true);
    if (imdbId == null) return const [];
    return const OpenSubtitlesService().searchMovie(imdbId);
  }

  /// Fetch external subtitles for a TV episode using TMDB ID, season, and episode
  Future<List<ExternalSubtitle>> fetchTVSubtitles(
    int tmdbId,
    int seasonNumber,
    int episodeNumber,
  ) async {
    try {
      final fromScraper = await ScraperApi(scraperApiUrl).searchSubtitles(
        tmdbId: tmdbId,
        season: seasonNumber,
        episode: episodeNumber,
      );
      if (fromScraper.isNotEmpty) return fromScraper;
    } catch (_) {
      // Fall through to the OpenSubtitles fallback below.
    }
    final imdbId = await const OpenSubtitlesService()
        .fetchImdbId(tmdbId: tmdbId, isMovie: false);
    if (imdbId == null) return const [];
    return const OpenSubtitlesService()
        .searchEpisode(imdbId, seasonNumber, episodeNumber);
  }

  /// Download and convert ExternalSubtitle to BetterPlayerSubtitlesSource with parsed content
  static Future<BetterPlayerSubtitlesSource> convertToBetterPlayerSource(
    ExternalSubtitle subtitle, {
    int? subtitleNumber,
  }) async {
    final subtitleContent = await _downloadSubtitle(subtitle.url);

    // The API serves WebVTT and SubRip; only WebVTT timestamps need fixing.
    final processedContent =
        subtitleContent.isEmpty || subtitle.format.toLowerCase() == 'srt'
            ? subtitleContent
            : processVttFileTimestamps(subtitleContent);

    // Create a unique name for the subtitle
    String subtitleName = subtitle.display;
    if (subtitleNumber != null) {
      subtitleName = '${subtitle.display} #$subtitleNumber';
    }
    if (subtitle.isHearingImpaired) {
      subtitleName += ' (HI)';
    }

    return BetterPlayerSubtitlesSource(
      type: BetterPlayerSubtitlesSourceType.memory,
      name: subtitleName,
      content: processedContent,
      selectedByDefault: false,
    );
  }

  /// Downloads a subtitle file from the API, which always answers in UTF-8, so
  /// malformed bytes are replaced instead of probed for a code page.
  /// OpenSubtitles download links serve gzip-compressed files, which are
  /// transparently decompressed first. Sends browser-identical headers and
  /// retries gateway errors.
  static Future<String> _downloadSubtitle(String url) async {
    return _downloadViaHttp(url);
  }

  static Future<String> _downloadViaHttp(String url) async {
    // Mirror a real Chrome-for-Android request as closely as possible: the
    // download host serves browsers fine but rejects bare-bones clients.
    const downloadHeaders = {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'none',
      'Sec-Fetch-User': '?1',
    };
    Exception? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: downloadHeaders)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          final decoded = _decodeSubtitleBytes(response.bodyBytes);
          // An error page is never a subtitle file.
          return decoded.trimLeft().startsWith('<') ? '' : decoded;
        }
        lastError = Exception('HTTP ${response.statusCode}');
        // Only gateway errors are worth retrying; other statuses won't
        // fix themselves with another attempt.
        if (response.statusCode != 502 &&
            response.statusCode != 503 &&
            response.statusCode != 504) {
          break;
        }
      } on SocketException catch (e) {
        lastError = Exception('Download failed: $e');
      } on TimeoutException catch (e) {
        lastError = Exception('Download failed: $e');
      } catch (e) {
        lastError = Exception('Download failed: $e');
        break;
      }
      if (attempt < 2) {
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
    throw lastError ?? Exception('Download failed');
  }

  /// Decompresses gzip-compressed subtitle files (OpenSubtitles serves .gz),
  /// falling back to plain UTF-8 decoding for regular files.
  static String _decodeSubtitleBytes(List<int> bytes) {
    try {
      return utf8.decode(gzip.decode(bytes), allowMalformed: true);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}
