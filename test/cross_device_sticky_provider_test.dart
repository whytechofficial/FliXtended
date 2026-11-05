import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';
import 'package:flixquest/constants/app_constants.dart';
import 'package:flixquest/controllers/recently_watched_database_controller.dart';
import 'package:flixquest/models/movie_stream_metadata.dart';
import 'package:flixquest/models/recently_watched.dart';
import 'package:flixquest/models/tv_stream_metadata.dart';
import 'package:flixquest/provider/recently_watched_provider.dart';
import 'package:flixquest/provider/settings_provider.dart';
import 'package:flixquest/screens/common/player/player_data_management.dart';
import 'package:flixquest/services/recently_watched_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Item 8: the provider a title played on must survive a device change.
/// The chain under test, end to end at unit level:
///   phone player save (provider on the row) -> cloud map -> fresh device
///   (cloud map parsed, winners seeded) -> loader's sticky lookup.
/// The loader's sticky-first ordering given a sticky value is already
/// pinned by played_provider_sticky_test; this file pins the sync bridge
/// that puts the value there on a device that never played the title.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sharedPrefsSingleton = await SharedPreferences.getInstance();
  });

  RecentMovie phoneMovie() => RecentMovie(
        backdropPath: '/backdrop.jpg',
        dateTime: '2026-11-05 02:00:00.000',
        elapsed: 6360,
        id: 550,
        posterPath: '/poster.jpg',
        releaseYear: 1999,
        remaining: 1200,
        title: 'Fight Club',
        providerCode: 'scraper:aethoflix',
      );

  RecentEpisode phoneEpisode() => RecentEpisode(
        dateTime: '2026-11-05 02:00:00.000',
        elapsed: 900,
        episodeName: 'Pilot',
        episodeNum: 1,
        id: 62085,
        posterPath: '/poster.jpg',
        backdropPath: '/still.jpg',
        remaining: 1200,
        seasonNum: 1,
        seriesName: 'Breaking Bad',
        seriesId: 1396,
        providerCode: 'scraper:aethoflix',
      );

  group('providerCode in the synced record', () {
    test('movie cloud round trip preserves the played provider', () {
      final restored = RecentMovie.fromCloudMap(phoneMovie().toCloudMap());

      expect(restored.id, 550);
      expect(restored.providerCode, 'scraper:aethoflix');
      expect(restored.elapsed, 6360);
    });

    test('episode cloud round trip preserves the played provider', () {
      final restored = RecentEpisode.fromCloudMap(phoneEpisode().toCloudMap());

      expect(restored.id, 62085);
      expect(restored.seriesId, 1396);
      expect(restored.providerCode, 'scraper:aethoflix');
    });

    test('a provider-less cloud map means unknown, not a provider', () {
      final movie =
          RecentMovie.fromCloudMap(<String, dynamic>{'id': 550});
      final episode = RecentEpisode.fromCloudMap(<String, dynamic>{
        'id': 62085,
        'seriesId': 1396,
      });

      expect(movie.providerCode, isNull);
      expect(episode.providerCode, isNull);
    });

    test('a null provider is omitted from the cloud map, never sent', () {
      final movie = phoneMovie()..providerCode = null;

      expect(movie.toCloudMap().containsKey('providerCode'), isFalse);
      expect(
        phoneMovie().toCloudMap()['providerCode'],
        'scraper:aethoflix',
      );
    });

    test('local database round trip preserves the provider', () {
      final movie = RecentMovie.fromMapObject(phoneMovie().toMap());
      final episode = RecentEpisode.fromMapObject(phoneEpisode().toMap());

      expect(movie.providerCode, 'scraper:aethoflix');
      expect(episode.providerCode, 'scraper:aethoflix');
    });
  });

  group('seedStickyProvidersFromCloud on a fresh device', () {
    test('a synced movie provider becomes the fresh device sticky', () async {
      // Simulate the network hop: phone row -> cloud map -> fresh device.
      final pulled =
          RecentMovie.fromCloudMap(phoneMovie().toCloudMap());
      await seedStickyProvidersFromCloud(
        movies: [pulled],
        episodes: const <RecentEpisode>[],
      );

      // A brand-new SettingsProvider on this device (no local sticky ever
      // written here) reads the seeded value: the loader will race
      // Karamara first instead of Zeila.
      expect(SettingsProvider().getLastMovieProvider(550),
          'scraper:aethoflix');
    });

    test('a synced episode provider seeds by series, not episode', () async {
      final pulled =
          RecentEpisode.fromCloudMap(phoneEpisode().toCloudMap());
      await seedStickyProvidersFromCloud(
        movies: const <RecentMovie>[],
        episodes: [pulled],
      );

      expect(
          SettingsProvider().getLastTvProvider(1396), 'scraper:aethoflix');
      // The episode id is not a sticky key: the TV loader looks the series
      // up, so seeding the episode id would seed nothing the loader reads.
      expect(SettingsProvider().getLastTvProvider(62085), isNull);
    });

    test('tombstones and provider-less rows seed nothing', () async {
      final deleted = phoneMovie()..deletedAtUtc = 9999;
      final unknown = phoneMovie()
        ..id = 551
        ..providerCode = null;
      await seedStickyProvidersFromCloud(
        movies: [deleted, unknown],
        episodes: const <RecentEpisode>[],
      );

      expect(SettingsProvider().getLastMovieProvider(550), isNull);
      expect(SettingsProvider().getLastMovieProvider(551), isNull);
    });
  });

  group('player saves carry the playing provider', () {
    late _Movies movies;
    late _Episodes episodes;
    late _Recent recent;
    late PlayerDataManagement data;
    late BuildContext context;

    Future<void> mount(WidgetTester tester) async {
      movies = _Movies();
      episodes = _Episodes();
      recent = _Recent();
      data = PlayerDataManagement(
        recentlyWatchedMoviesController: movies,
        recentlyWatchedEpisodeController: episodes,
      );
      addTearDown(recent.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<RecentProvider>.value(
          value: recent,
          child: Builder(builder: (value) {
            context = value;
            return const SizedBox();
          }),
        ),
      );
    }

    testWidgets('movie save stores the playing provider on the row',
        (tester) async {
      await mount(tester);
      final video = _Video(50);
      addTearDown(video.dispose);
      movies.contains.complete(false);
      await data.insertRecentMovieData(
        context: context,
        betterPlayerController: _Player(video),
        duration: 100,
        movieMetadata: MovieStreamMetadata(
          movieId: 550,
          movieName: 'Fight Club',
          posterPath: '/poster.jpg',
          backdropPath: '/backdrop.jpg',
          releaseYear: 1999,
          elapsed: 0,
          isAdult: false,
          releaseDate: '1999-10-15',
        ),
        providerCode: 'scraper:aethoflix',
      );

      expect(recent.movie?.providerCode, 'scraper:aethoflix');
      expect(recent.movie?.elapsed, 50);
    });

    testWidgets('episode save stores the playing provider on the row',
        (tester) async {
      await mount(tester);
      final video = _Video(50);
      addTearDown(video.dispose);
      episodes.contains.complete(false);
      await data.insertRecentEpisodeData(
        context: context,
        betterPlayerController: _Player(video),
        duration: 100,
        tvMetadata: TVStreamMetadata(
          tvId: 1396,
          episodeId: 62085,
          seriesName: 'Breaking Bad',
          episodeName: 'Pilot',
          episodeNumber: 1,
          seasonNumber: 1,
          posterPath: '/poster.jpg',
          elapsed: 0,
          airDate: '2008-01-20',
          seasonEpisodes: const [],
        ),
        providerCode: 'scraper:aethoflix',
      );

      expect(recent.episode?.providerCode, 'scraper:aethoflix');
    });

    testWidgets('a provider-less save keeps the row sticky it already had',
        (tester) async {
      await mount(tester);
      recent.storedMovies = [phoneMovie()];
      final video = _Video(50);
      addTearDown(video.dispose);
      movies.contains.complete(true);
      await data.insertRecentMovieData(
        context: context,
        betterPlayerController: _Player(video),
        duration: 100,
        movieMetadata: MovieStreamMetadata(
          movieId: 550,
          movieName: 'Fight Club',
          posterPath: '/poster.jpg',
          backdropPath: '/backdrop.jpg',
          releaseYear: 1999,
          elapsed: 0,
          isAdult: false,
          releaseDate: '1999-10-15',
        ),
      );

      expect(recent.movie?.providerCode, 'scraper:aethoflix');
    });
  });
}

class _Movies implements RecentlyWatchedMoviesController {
  final contains = Completer<bool>();

  @override
  Future<bool> contain(int id) => contains.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Episodes implements RecentlyWatchedEpisodeController {
  final contains = Completer<bool>();

  @override
  Future<bool> contain(int id) => contains.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Video implements VideoPlayerController {
  _Video(int elapsed)
      : value = VideoPlayerValue(
          duration: const Duration(seconds: 100),
          position: Duration(seconds: elapsed),
        );

  @override
  VideoPlayerValue value;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements BetterPlayerController {
  _Player(this.videoPlayerController);

  @override
  VideoPlayerController? videoPlayerController;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recent extends ChangeNotifier implements RecentProvider {
  List<RecentMovie> storedMovies = [];
  List<RecentEpisode> storedEpisodes = [];
  RecentMovie? movie;
  RecentEpisode? episode;

  @override
  List<RecentMovie> get movies => storedMovies;

  @override
  List<RecentEpisode> get episodes => storedEpisodes;

  @override
  Future<void> addMovie(RecentMovie value) async {
    movie = value;
  }

  @override
  Future<void> updateMovie(RecentMovie value, int id) async {
    movie = value;
  }

  @override
  Future<void> addEpisode(RecentEpisode value) async {
    episode = value;
  }

  @override
  Future<void> updateEpisode(
      RecentEpisode value, int id, int episodeNum, int seasonNum) async {
    episode = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
