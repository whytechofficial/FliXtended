import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../api/endpoints.dart';
import '../models/external_subtitles.dart';
import '../preferences/setting_preferences.dart';

/// Key-free OpenSubtitles fallback (rest.opensubtitles.org).
///
/// Used when the scraper API's own subtitle search fails or returns nothing.
/// Search is by IMDB id (resolved from TMDB through the app's proxy); the
/// download links serve gzip-compressed files, which are decompressed before
/// being handed to the player. No API key, no login.
class OpenSubtitlesService {
  const OpenSubtitlesService();

  static const _searchBase = 'https://rest.opensubtitles.org/search';
  static const _userAgent = 'FliXtended';

  /// Resolves a TMDB id to a bare IMDB id (without the "tt" prefix) through
  /// the app's TMDB proxy. Returns null when it cannot be resolved.
  Future<String?> fetchImdbId({
    required int tmdbId,
    required bool isMovie,
  }) async {
    try {
      final url = isMovie
          ? Endpoints.getExternalLinksForMovie(tmdbId, 'en')
          : Endpoints.getExternalLinksForTV(tmdbId, 'en');
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      final imdbId = body is Map ? body['imdb_id']?.toString() : null;
      if (imdbId == null || imdbId.isEmpty) return null;
      return imdbId.startsWith('tt') ? imdbId.substring(2) : imdbId;
    } catch (_) {
      return null;
    }
  }

  /// Searches subtitles for a movie by IMDB id.
  Future<List<ExternalSubtitle>> searchMovie(String imdbId) {
    return _search(imdbId: imdbId);
  }

  /// Searches subtitles for a TV episode by IMDB id, season and episode.
  /// Falls back to the whole-series result when the episode-scoped search
  /// comes back empty.
  Future<List<ExternalSubtitle>> searchEpisode(
    String imdbId,
    int season,
    int episode,
  ) async {
    final scoped = await _search(imdbId: imdbId, season: season, episode: episode);
    if (scoped.isNotEmpty) return scoped;
    return _search(imdbId: imdbId);
  }

  Future<List<ExternalSubtitle>> _search({
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    try {
      final parts = <String>['imdbid-$imdbId'];
      if (season != null) parts.add('season-$season');
      if (episode != null) parts.add('episode-$episode');
      parts.add('sublanguageid-all');
      final uri = Uri.parse('$_searchBase/${parts.join('/')}');
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      final raws = decoded.whereType<Map>().toList(growable: true);
      // Smart ordering: the user's preferred language first, then the
      // subtitles most likely to be in sync (non-HI, higher rated, more
      // downloaded, srt). Same-release timing mismatches are the main cause
      // of out-of-sync subtitles, so the best candidates float to the top.
      final preferred = await _preferredLanguage();
      raws.sort((a, b) => _compareRaw(a, b, preferred));
      return raws
          .map(_toExternalSubtitle)
          .where((subtitle) => subtitle.url.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<String> _preferredLanguage() async {
    try {
      return await SettingsPreferences().getSubLanguage();
    } catch (_) {
      return 'en';
    }
  }

  /// OpenSubtitles 3-letter codes to the 2-letter codes the app uses.
  static const _languageMap = {
    'eng': 'en',
    'hin': 'hi',
    'ara': 'ar',
    'mal': 'ml',
    'tam': 'ta',
    'tel': 'te',
    'kan': 'kn',
    'ben': 'bn',
    'urd': 'ur',
    'pan': 'pa',
    'guj': 'gu',
    'mar': 'mr',
    'spa': 'es',
    'fre': 'fr',
    'por': 'pt',
    'ger': 'de',
    'ita': 'it',
    'rus': 'ru',
    'jpn': 'ja',
    'kor': 'ko',
    'chi': 'zh',
    'zho': 'zh',
    'dut': 'nl',
    'nld': 'nl',
    'swe': 'sv',
    'nor': 'no',
    'dan': 'da',
    'fin': 'fi',
    'pol': 'pl',
    'tur': 'tr',
    'tha': 'th',
    'vie': 'vi',
    'ind': 'id',
    'msa': 'ms',
  };

  static String _normalizeLanguage(String code) {
    final lower = code.toLowerCase();
    if (lower.length == 2) return lower;
    return _languageMap[lower] ?? lower;
  }

  static String _rawLanguage(Map raw) =>
      (raw['SubLanguageID']?.toString() ?? 'en').toLowerCase();

  static bool _rawHearingImpaired(Map raw) {
    final value = raw['SubHearingImpaired']?.toString() ?? '0';
    return value == '1' || value.toLowerCase() == 'true';
  }

  static double _rawRating(Map raw) =>
      double.tryParse(raw['SubRating']?.toString() ?? '') ?? 0;

  static int _rawDownloads(Map raw) =>
      int.tryParse(raw['SubDownloadsCnt']?.toString() ?? '') ?? 0;

  int _compareRaw(Map a, Map b, String preferred) {
    // Preferred language first.
    final aPreferred = _normalizeLanguage(_rawLanguage(a)) == preferred ? 0 : 1;
    final bPreferred = _normalizeLanguage(_rawLanguage(b)) == preferred ? 0 : 1;
    if (aPreferred != bPreferred) return aPreferred - bPreferred;
    // Non hearing-impaired before HI.
    final aHi = _rawHearingImpaired(a) ? 1 : 0;
    final bHi = _rawHearingImpaired(b) ? 1 : 0;
    if (aHi != bHi) return aHi - bHi;
    // Higher rated first.
    final rating = _rawRating(b).compareTo(_rawRating(a));
    if (rating != 0) return rating;
    // More downloaded first.
    final downloads = _rawDownloads(b).compareTo(_rawDownloads(a));
    if (downloads != 0) return downloads;
    // srt before other formats.
    final aSrt = (a['SubFormat']?.toString() ?? '').toLowerCase() == 'srt' ? 0 : 1;
    final bSrt = (b['SubFormat']?.toString() ?? '').toLowerCase() == 'srt' ? 0 : 1;
    return aSrt - bSrt;
  }

  ExternalSubtitle _toExternalSubtitle(Map raw) {
    final subtitle = Map<String, dynamic>.from(raw);
    final language =
        (subtitle['SubLanguageID']?.toString() ?? 'en').toLowerCase();
    final fileName = subtitle['SubFileName']?.toString() ?? '';
    final release = subtitle['InfoReleaseGroup']?.toString() ?? '';
    final display = StringBuffer(language.toUpperCase());
    if (fileName.isNotEmpty) display.write(' · $fileName');
    return ExternalSubtitle(
      id: subtitle['IDSubtitleFile']?.toString() ?? '',
      url: subtitle['SubDownloadLink']?.toString() ?? '',
      flagUrl: '',
      format: (subtitle['SubFormat']?.toString() ?? 'srt').toLowerCase(),
      encoding: 'UTF-8',
      display: display.toString(),
      language: language,
      media: '',
      isHearingImpaired: _rawHearingImpaired(subtitle),
      release: release,
    );
  }

  /// Downloads a subtitle file, transparently handling the gzip compression
  /// that SubDownloadLink serves. Returns the subtitle text, or '' when the
  /// download fails or is not actually a subtitle file.
  static Future<String> downloadContent(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return '';
      final text = _decodeBytes(response.bodyBytes);
      return text.trimLeft().startsWith('<') ? '' : text;
    } catch (_) {
      return '';
    }
  }

  static String _decodeBytes(List<int> bytes) {
    try {
      return utf8.decode(gzip.decode(bytes), allowMalformed: true);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}
