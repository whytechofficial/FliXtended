import 'package:flixquest/constants/app_constants.dart';
import 'package:flixquest/preferences/setting_preferences.dart';
import 'package:flixquest/provider/settings_provider.dart';
import 'package:flixquest/video_providers/category_order.dart';
import 'package:flixquest/video_providers/names.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

VideoProvider _scraper(String id, String name) =>
    VideoProvider.scraper(id: id, name: name);

List<String> _codes(List<VideoProvider> providers) =>
    providers.map((provider) => provider.codeName).toList();

/// The loader's two steps, in loader order: category order first, then
/// the sticky moved to the front. Mirrors movie_video_loader and
/// tv_video_loader, so these tests pin the invariant sticky > category
/// > default rather than either step alone.
List<VideoProvider> _loaderOrder(
  List<VideoProvider> ordered, {
  required List<String> countries,
  String? sticky,
}) {
  var tryProviders = applyCategoryOrder(
    ordered,
    countries: countries,
    genres: const <String>[],
    languages: const <String>[],
  );
  if (sticky != null) {
    final index =
        tryProviders.indexWhere((provider) => provider.codeName == sticky);
    if (index > 0) {
      final provider = tryProviders.removeAt(index);
      tryProviders = <VideoProvider>[provider, ...tryProviders];
    }
  }
  return tryProviders;
}

/// The default try order an upgrading user sees: Zeila, Abyssinia,
/// Gura first, Karamara later.
final _defaultOrdered = <VideoProvider>[
  _scraper('movy', 'Zeila'),
  _scraper('cinejoy', 'Abyssinia'),
  _scraper('vidup', 'Gura'),
  _scraper('aethoflix', 'Karamara'),
  VideoProvider.directCastle,
  VideoProvider.directNetMirror,
  VideoProvider.directMxPlayer,
  VideoProvider.directVixSrc,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sharedPrefsSingleton = await SharedPreferences.getInstance();
  });

  group('recordPlayedProvider', () {
    test('records the race winner for a movie, not only a manual pick',
        () async {
      final settings = SettingsProvider();
      await settings.recordPlayedProvider(
        isTv: false,
        movieId: 101,
        tvId: null,
        providerCode: 'scraper:movy',
      );
      expect(settings.getLastMovieProvider(101), 'scraper:movy');
    });

    test('records the race winner for a series', () async {
      final settings = SettingsProvider();
      await settings.recordPlayedProvider(
        isTv: true,
        movieId: null,
        tvId: 202,
        providerCode: 'scraper:movy',
      );
      expect(settings.getLastTvProvider(202), 'scraper:movy');
    });

    test('a later manual switch overwrites the recorded winner', () async {
      final settings = SettingsProvider();
      await settings.recordPlayedProvider(
        isTv: false,
        movieId: 101,
        tvId: null,
        providerCode: 'scraper:movy',
      );
      expect(settings.getLastMovieProvider(101), 'scraper:movy');
      // The manual-switch path writes through the same setters.
      await settings.setLastMovieProvider(101, 'scraper:aethoflix');
      expect(settings.getLastMovieProvider(101), 'scraper:aethoflix');
    });

    test('a later playback overwrites an earlier manual pick', () async {
      final settings = SettingsProvider();
      await settings.setLastTvProvider(202, 'scraper:aethoflix');
      await settings.recordPlayedProvider(
        isTv: true,
        movieId: null,
        tvId: 202,
        providerCode: 'scraper:movy',
      );
      expect(settings.getLastTvProvider(202), 'scraper:movy');
    });

    test('null or blank codes and missing ids record nothing', () async {
      final settings = SettingsProvider();
      await settings.recordPlayedProvider(
        isTv: false,
        movieId: 101,
        tvId: null,
        providerCode: null,
      );
      await settings.recordPlayedProvider(
        isTv: false,
        movieId: 102,
        tvId: null,
        providerCode: '   ',
      );
      await settings.recordPlayedProvider(
        isTv: false,
        movieId: null,
        tvId: null,
        providerCode: 'scraper:movy',
      );
      await settings.recordPlayedProvider(
        isTv: true,
        movieId: null,
        tvId: null,
        providerCode: 'scraper:movy',
      );
      expect(settings.getLastMovieProvider(101), isNull);
      expect(settings.getLastMovieProvider(102), isNull);
      expect(settings.getLastTvProvider(202), isNull);
    });

    test('a recorded sticky survives a fresh provider instance', () async {
      // A source refresh records nothing and a restart reloads from
      // the same preferences, so neither clears the sticky.
      final settings = SettingsProvider();
      await settings.recordPlayedProvider(
        isTv: false,
        movieId: 101,
        tvId: null,
        providerCode: 'scraper:movy',
      );
      final reloaded = SettingsProvider();
      await reloaded.getStreamProviderOrder();
      expect(reloaded.getLastMovieProvider(101), 'scraper:movy');
    });
  });

  group('sticky against category order', () {
    test('an Indian title with a Zeila sticky resumes on Zeila', () async {
      final settings = SettingsProvider();
      await settings.recordPlayedProvider(
        isTv: false,
        movieId: 101,
        tvId: null,
        providerCode: 'scraper:movy',
      );
      final ordered = _loaderOrder(
        _defaultOrdered,
        countries: const ['India'],
        sticky: settings.getLastMovieProvider(101),
      );
      // Zeila first — not Karamara — with the category order intact
      // behind it.
      expect(
        _codes(ordered).take(5),
        [
          'scraper:movy',
          'scraper:aethoflix',
          'direct:castle',
          'direct:netmirror',
          'direct:mxplayer',
        ],
      );
    });

    test('an Indian title with no sticky still tries Karamara first',
        () async {
      final ordered = _loaderOrder(
        _defaultOrdered,
        countries: const ['India'],
      );
      expect(
        _codes(ordered).take(4),
        [
          'scraper:aethoflix',
          'direct:castle',
          'direct:netmirror',
          'direct:mxplayer',
        ],
      );
    });
  });
}
