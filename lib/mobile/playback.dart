import 'package:flixquest/services/adsterra_playback_ads_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../catalog/details_controller.dart';
import '../catalog/details_play.dart';
import '../catalog/episode_choice.dart';
import '../catalog/media_item.dart';
import '../catalog/up_next.dart';
import '../functions/function.dart';
import '../functions/network.dart';
import '../models/movie.dart';
import '../models/movie_stream_metadata.dart';
import '../models/recently_watched.dart';
import '../models/tv.dart';
import '../models/tv_stream_metadata.dart';
import '../provider/app_dependency_provider.dart';
import '../provider/recently_watched_provider.dart';
import '../provider/settings_provider.dart';
import '../screens/movie/movie_detail.dart';
import '../screens/movie/movie_video_loader.dart';
import '../screens/tv/tv_detail.dart';
import '../screens/tv/tv_video_loader.dart';

/// Opening and playing titles from the phone's browse pages.
abstract final class MobilePlayback {
  /// Whether Play is offered at all; the remote config can turn it off.
  static bool canPlay(BuildContext context) =>
      context.read<AppDependencyProvider?>()?.displayWatchNowButton ?? true;

  /// Where [item] would pick up, from what the viewer has watched.
  static ResumePoint? resumeFor(BuildContext context, MediaItem item) {
    final recent = context.read<RecentProvider?>();
    if (recent == null) return null;
    return ResumePoint.forItem(
      item,
      movies: recent.movies,
      episodes: recent.episodes,
    );
  }

  static Future<void> openDetails(BuildContext context, MediaItem item) {
    final heroId = 'mobile-${item.stableId}';
    final Widget page = item.kind == MediaKind.movie
        ? MovieDetailPage(
            movie: item.movie ??
                Movie(
                  id: item.id,
                  title: item.title,
                  posterPath: item.posterPath,
                  backdropPath: item.backdropPath,
                  overview: item.overview,
                  releaseDate: item.releaseDate,
                  voteAverage: item.rating,
                ),
            heroId: heroId,
          )
        : TVDetailPage(
            tvSeries: item.series ??
                TV(
                  id: item.id,
                  name: item.title,
                  originalName: item.title,
                  posterPath: item.posterPath,
                  backdropPath: item.backdropPath,
                  overview: item.overview,
                  firstAirDate: item.releaseDate,
                  voteAverage: item.rating,
                ),
            heroId: heroId,
          );
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  /// Plays [item] from where the viewer is: a movie part way through, a
  /// series at its episode in progress or the next one, else from the start.
  /// Opens the details page instead when playing is turned off.
  /// [onReady] dismisses an originating sheet once preparation is complete;
  /// returning false cancels playback if that sheet has already been left.
  static Future<void> play(
    BuildContext context,
    MediaItem item, {
    bool Function()? onReady,
  }) async {
    if (!canPlay(context)) {
      if (onReady?.call() == false) return;
      return openDetails(context, item);
    }
    final resume = resumeFor(context, item);
    if (!await _online(context) || !context.mounted) return;
    if (item.kind == MediaKind.movie) {
      return _playMovie(context, item,
          elapsed: resume?.elapsed, onReady: onReady);
    }
    final recent = context.read<RecentProvider?>();
    final next = upNextFor(
      item,
      episodes: recent?.episodes ?? const <RecentEpisode>[],
      upNext: recent?.upNext ?? const <UpNext>[],
    );
    return _playSeries(context, item, next == null ? resume : null, next,
        onReady: onReady);
  }

  static Future<bool> _online(BuildContext context) async {
    if (await checkConnection()) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('check_connection'))),
      );
    }
    return false;
  }

  static Future<void> _playMovie(
    BuildContext context,
    MediaItem item, {
    int? elapsed,
    bool Function()? onReady,
  }) async {
    // The host must be current before presenting a before-loader ad.
    // Settings and dependencies are read before the first await, so the
    // details fetch below never holds a context across an async gap.
    if (onReady?.call() == false) return;
    final settings = context.read<SettingsProvider>();
    final dependencies = context.read<AppDependencyProvider>();
    if (!await AdsterraPlaybackAdsService.instance.beforeLoader(context) ||
        !context.mounted) {
      return;
    }
    final movie = item.movie;
    debugPrint(
      '[MovieRecommendationsDebug][MOBILE_PLAYBACK_PLAY] '
      'movieId=${item.id} title=${item.title} '
      'recommendationsProvided=false (fetched by MovieVideoLoader)',
    );
    // Resume plays used to hand the loader no countries at all, so an
    // Indian film resumed from Continue Watching kept the plain default
    // order even with category ordering on. The details fetch is quiet:
    // when it fails, playback proceeds exactly as before, unordered.
    // Genre names are not in MovieDetails, so anime resumed from here
    // still keeps the default order; Indian and Turkish do not.
    MovieDetails? details;
    try {
      details = await fetchMovieDetails(
        Endpoints.movieDetailsUrl(item.id, settings.appLanguage),
        settings.enableProxy,
        dependencies.tmdbProxy,
      );
    } catch (_) {
      details = null;
    }
    final insights = details == null
        ? null
        : insightsMetadata(
            genres: const <String>[],
            movie: details,
            originalLanguage: movie?.originalLanguage,
          );
    final metadata = MovieStreamMetadata(
      backdropPath: item.backdropPath,
      elapsed: elapsed,
      movieId: item.id,
      movieName: item.title,
      posterPath: item.posterPath,
      releaseYear:
          int.tryParse(item.year ?? '') ?? item.recentMovie?.releaseYear ?? 0,
      isAdult: movie?.adult,
      releaseDate: item.releaseDate ?? movie?.releaseDate,
      genres: insights?.genres ?? const <String>[],
      languages: insights?.languages ?? const <String>[],
      countries: insights?.countries ?? const <String>[],
    );
    if (!context.mounted) return;
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MovieVideoLoader(
          download: false,
          metadata: metadata,
        ),
      ),
    );
  }

  static Future<void> _playSeries(
    BuildContext context,
    MediaItem item,
    ResumePoint? resume,
    UpNext? upNext, {
    bool Function()? onReady,
  }) async {
    final settings = context.read<SettingsProvider>();
    final dependencies = context.read<AppDependencyProvider>();
    const controller = MediaDetailsController();
    try {
      final details = await controller.load(
        item: item,
        settings: settings,
        dependencies: dependencies,
      );
      final choice = await chooseEpisode(
        seasons: details.seasons,
        resume: resume,
        upNext: upNext,
        loadSeason: (season) => controller.loadSeason(
          seriesId: item.id,
          seasonNumber: season,
          settings: settings,
          dependencies: dependencies,
        ),
      );
      if (choice == null || !context.mounted) return;
      if (onReady?.call() == false) return;
      if (!await AdsterraPlaybackAdsService.instance.beforeLoader(context) ||
          !context.mounted) {
        return;
      }
      final episode = choice.episode;
      // Same gap as the movie path above: the series details are already
      // loaded here, so their countries and languages ride along. Genre
      // names are not in TVDetails, so anime resumed from here still
      // keeps the default order; Indian and Turkish do not.
      final seriesInsights = details.seriesDetails == null
          ? null
          : insightsMetadata(
              genres: const <String>[],
              series: details.seriesDetails,
              originalLanguage: item.series?.originalLanguage,
            );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TVVideoLoader(
            download: false,
            metadata: TVStreamMetadata(
              elapsed: choice.elapsed,
              episodeId: episode.episodeId,
              episodeName: episode.name,
              episodeNumber: episode.episodeNumber,
              posterPath: item.posterPath,
              backdropPath: episode.stillPath ?? item.backdropPath,
              seasonNumber: episode.seasonNumber,
              seriesName: item.title,
              tvId: item.id,
              airDate: episode.airDate,
              genres: seriesInsights?.genres ?? const <String>[],
              languages: seriesInsights?.languages ?? const <String>[],
              countries: seriesInsights?.countries ?? const <String>[],
              seasonEpisodes: choice.seasonEpisodes
                  .where((episode) => episode.episodeId != null)
                  .map(EpisodeMetadata.fromEpisodeList)
                  .toList(growable: false),
              allSeasons: details.seriesDetails?.seasons
                  ?.where((season) => season.seasonNumber != null)
                  .map(SeasonMetadata.fromSeason)
                  .toList(growable: false),
            ),
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('episodes_load_failed'))),
        );
      }
    }
  }
}
