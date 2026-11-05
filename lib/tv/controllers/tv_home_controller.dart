import '../../api/endpoints.dart';
import '../../catalog/catalog_controller.dart';
import '../../catalog/home_feed_controller.dart' show RegionalLanguage;
import '../../functions/network.dart';
import '../../provider/app_dependency_provider.dart';
import '../../provider/settings_provider.dart';
import '../models/tv_media_item.dart';

class TvHomeData {
  const TvHomeData({
    required this.popularMovies,
    required this.trendingMovies,
    required this.popularSeries,
    required this.trendingSeries,
    this.topMovies = const <TvMediaItem>[],
    this.topSeries = const <TvMediaItem>[],
    this.regionalMovies = const <String, List<TvMediaItem>>{},
    this.regionalSeries = const <String, List<TvMediaItem>>{},
  });

  final List<TvMediaItem> popularMovies;
  final List<TvMediaItem> trendingMovies;
  final List<TvMediaItem> popularSeries;
  final List<TvMediaItem> trendingSeries;

  /// Today's ten most watched, for the Top 10 rows.
  final List<TvMediaItem> topMovies;
  final List<TvMediaItem> topSeries;

  /// The regional Top 10 rows, by [RegionalLanguage] code — the same rows
  /// and order as the phone's Home, fed by the same discover queries.
  /// Extras like the Top 10s: a missing one leaves the rest standing, and
  /// they do not count towards [isEmpty].
  final Map<String, List<TvMediaItem>> regionalMovies;
  final Map<String, List<TvMediaItem>> regionalSeries;

  TvMediaItem? get hero {
    if (trendingMovies.isNotEmpty) return trendingMovies.first;
    if (trendingSeries.isNotEmpty) return trendingSeries.first;
    if (popularMovies.isNotEmpty) return popularMovies.first;
    if (popularSeries.isNotEmpty) return popularSeries.first;
    return null;
  }

  bool get isEmpty =>
      popularMovies.isEmpty &&
      trendingMovies.isEmpty &&
      popularSeries.isEmpty &&
      trendingSeries.isEmpty;
}

class TvHomeController {
  const TvHomeController();

  Future<TvHomeData> load({
    required SettingsProvider settings,
    required AppDependencyProvider dependencies,
  }) async {
    final language = settings.appLanguage;
    // The same lists the rows' See all opens.
    String url(TvMediaKind kind, CatalogList list) =>
        CatalogController.listUrl(kind, list, language);
    final popularMoviesFuture = fetchMovies(
      url(TvMediaKind.movie, CatalogList.popular),
      settings.enableProxy,
      dependencies.tmdbProxy,
    );
    final trendingMoviesFuture = fetchMovies(
      url(TvMediaKind.movie, CatalogList.trendingWeek),
      settings.enableProxy,
      dependencies.tmdbProxy,
    );
    final popularSeriesFuture = fetchTV(
      url(TvMediaKind.series, CatalogList.popular),
      settings.enableProxy,
      dependencies.tmdbProxy,
    );
    final trendingSeriesFuture = fetchTV(
      url(TvMediaKind.series, CatalogList.trendingWeek),
      settings.enableProxy,
      dependencies.tmdbProxy,
    );

    // The Top 10 rows are extras: without them the page still stands.
    final topMoviesFuture = fetchMovies(
      url(TvMediaKind.movie, CatalogList.trendingToday),
      settings.enableProxy,
      dependencies.tmdbProxy,
    ).then(
      (items) => items.take(10).map(TvMediaItem.fromMovie).toList(),
      onError: (Object _) => <TvMediaItem>[],
    );
    final topSeriesFuture = fetchTV(
      url(TvMediaKind.series, CatalogList.trendingToday),
      settings.enableProxy,
      dependencies.tmdbProxy,
    ).then(
      (items) => items.take(10).map(TvMediaItem.fromSeries).toList(),
      onError: (Object _) => <TvMediaItem>[],
    );

    // The regional Top 10s: one discover per language and kind, each
    // failing on its own like every other extra row.
    final regionalMoviesFutures = <Future<List<TvMediaItem>>>[
      for (final regional in RegionalLanguage.values)
        fetchMovies(
          Endpoints.discoverMoviesByLanguageUrl(language, regional.code),
          settings.enableProxy,
          dependencies.tmdbProxy,
        ).then(
          (items) => items.take(10).map(TvMediaItem.fromMovie).toList(),
          onError: (Object _) => <TvMediaItem>[],
        ),
    ];
    final regionalSeriesFutures = <Future<List<TvMediaItem>>>[
      for (final regional in RegionalLanguage.values)
        fetchTV(
          Endpoints.discoverSeriesByLanguageUrl(language, regional.code),
          settings.enableProxy,
          dependencies.tmdbProxy,
        ).then(
          (items) => items.take(10).map(TvMediaItem.fromSeries).toList(),
          onError: (Object _) => <TvMediaItem>[],
        ),
    ];

    final popularMovies = await popularMoviesFuture;
    final trendingMovies = await trendingMoviesFuture;
    final popularSeries = await popularSeriesFuture;
    final trendingSeries = await trendingSeriesFuture;

    return TvHomeData(
      popularMovies:
          popularMovies.map(TvMediaItem.fromMovie).toList(growable: false),
      trendingMovies:
          trendingMovies.map(TvMediaItem.fromMovie).toList(growable: false),
      popularSeries:
          popularSeries.map(TvMediaItem.fromSeries).toList(growable: false),
      trendingSeries:
          trendingSeries.map(TvMediaItem.fromSeries).toList(growable: false),
      topMovies: await topMoviesFuture,
      topSeries: await topSeriesFuture,
      regionalMovies: <String, List<TvMediaItem>>{
        for (var i = 0; i < RegionalLanguage.values.length; i++)
          RegionalLanguage.values[i].code:
              (await regionalMoviesFutures[i]).toList(growable: false),
      },
      regionalSeries: <String, List<TvMediaItem>>{
        for (var i = 0; i < RegionalLanguage.values.length; i++)
          RegionalLanguage.values[i].code:
              (await regionalSeriesFutures[i]).toList(growable: false),
      },
    );
  }
}
