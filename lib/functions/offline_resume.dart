// Pure rules for offline-download playback resume. The offline player
// persists its position per download id (see `SettingsPreferences`);
// these helpers decide when that saved position should be discarded
// instead of restored.
//
// Cross-device unification (beta63 item 9): the per-download position stays
// the offline player's own store and always wins on the device that wrote
// it, but the player ALSO mirrors its position into the title's synced
// recently-watched row, and falls back to that synced row when it has no
// local position. That is what lets a download watched to 1h46 on the phone
// resume at 1h46 on the TV — from the TV's own download (fallback) or from
// streaming (the online loader already reads the synced row). Only the
// position travels, never the downloaded file.

import '../models/offline_download.dart';
import '../models/recently_watched.dart';

/// Mirrors the streaming rule in `player_data_management.dart`: a title
/// watched past 85% counts as finished, so its resume point is discarded
/// instead of restored. An unknown duration can never clear a position.
bool shouldClearOfflineResume({
  required int positionMs,
  required int durationMs,
}) {
  if (durationMs <= 0 || positionMs <= 0) return false;
  return positionMs / durationMs > 0.85;
}

/// The synced title position for [download], in milliseconds, or null when
/// there is no synced row for it. This is the offline player's FALLBACK
/// only: a local per-download position, when one exists, always wins.
///
/// Identity is by TITLE, not by download id (a download id means nothing on
/// another device): a movie matches its synced row by movie id
/// ([OfflineDownload.contentId]); an episode matches by series id plus
/// season and episode number, because a download record carries no episode
/// id. A row with no elapsed time is not a resume point.
int? syncedResumeMsForDownload({
  required List<RecentMovie> movies,
  required List<RecentEpisode> episodes,
  required OfflineDownload download,
}) {
  final contentId = download.contentId;
  if (contentId == null) return null;
  if (download.mediaType == 'movie') {
    for (final movie in movies) {
      if (movie.id == contentId && (movie.elapsed ?? 0) > 0) {
        return movie.elapsed! * 1000;
      }
    }
    return null;
  }
  final season = download.seasonNumber;
  final episode = download.episodeNumber;
  if (season == null || episode == null) return null;
  for (final row in episodes) {
    if (row.seriesId == contentId &&
        row.seasonNum == season &&
        row.episodeNum == episode &&
        (row.elapsed ?? 0) > 0) {
      return row.elapsed! * 1000;
    }
  }
  return null;
}

/// The synced row an offline save mirrors into, for a movie download: the
/// existing row with only its progress fields moved, or a minimal new row
/// when the title was never streamed (title + poster only — later online
/// playback overwrites it with the full metadata row). A fresh
/// [updatedAtUtc] (the constructor default) makes the mirrored row win the
/// next merge, and [synced] stays false so it is pushed.
RecentMovie mirroredMovieRow({
  required RecentMovie? existing,
  required int movieId,
  required String title,
  required String? posterPath,
  required int elapsedSeconds,
  required int remainingSeconds,
}) {
  if (existing != null) {
    return RecentMovie(
      backdropPath: existing.backdropPath,
      dateTime: DateTime.now().toString(),
      elapsed: elapsedSeconds,
      id: existing.id ?? movieId,
      posterPath: existing.posterPath,
      releaseYear: existing.releaseYear,
      remaining: remainingSeconds,
      title: existing.title ?? title,
      providerCode: existing.providerCode,
    );
  }
  return RecentMovie(
    backdropPath: null,
    dateTime: DateTime.now().toString(),
    elapsed: elapsedSeconds,
    id: movieId,
    posterPath: posterPath,
    releaseYear: null,
    remaining: remainingSeconds,
    title: title,
  );
}

/// The synced row an offline save mirrors into, for an episode download.
/// An episode row's primary key is its episode id. Downloads enqueued
/// with one (post-beta64 TV downloads carry `episodeId`) create a minimal
/// row when streaming never did — series name + poster only, like the
/// movie mirror; later online playback overwrites it with the full
/// metadata row. Downloads without an episode id (everything enqueued
/// before beta64) still create nothing: inventing an id would collide
/// with other episodes of the same series.
RecentEpisode? mirroredEpisodeRow({
  required RecentEpisode? existing,
  required int elapsedSeconds,
  required int remainingSeconds,
  int? episodeId,
  int? seriesId,
  int? seasonNum,
  int? episodeNum,
  String? seriesName,
  String? episodeName,
  String? posterPath,
}) {
  if (existing != null) {
    return RecentEpisode(
      dateTime: DateTime.now().toString(),
      elapsed: elapsedSeconds,
      episodeName: existing.episodeName,
      episodeNum: existing.episodeNum,
      id: existing.id,
      posterPath: existing.posterPath,
      backdropPath: existing.backdropPath,
      remaining: remainingSeconds,
      seasonNum: existing.seasonNum,
      seriesName: existing.seriesName,
      seriesId: existing.seriesId,
      // Offline playback has no provider to record: keep the row's sticky
      // rather than blanking it.
      providerCode: existing.providerCode,
    );
  }
  if (episodeId == null ||
      seriesId == null ||
      seasonNum == null ||
      episodeNum == null) {
    return null;
  }
  return RecentEpisode(
    dateTime: DateTime.now().toString(),
    elapsed: elapsedSeconds,
    episodeName: episodeName,
    episodeNum: episodeNum,
    id: episodeId,
    posterPath: posterPath,
    remaining: remainingSeconds,
    seasonNum: seasonNum,
    seriesName: seriesName,
    seriesId: seriesId,
  );
}

/// The existing synced row an offline save should mirror into, if any:
/// the movie row for a movie download, or the episode row matching series +
/// season + episode for an episode download. Null when there is none.
RecentMovie? existingMovieRow({
  required List<RecentMovie> movies,
  required OfflineDownload download,
}) {
  final contentId = download.contentId;
  if (contentId == null) return null;
  for (final movie in movies) {
    if (movie.id == contentId) return movie;
  }
  return null;
}

RecentEpisode? existingEpisodeRow({
  required List<RecentEpisode> episodes,
  required OfflineDownload download,
}) {
  final contentId = download.contentId;
  final season = download.seasonNumber;
  final episode = download.episodeNumber;
  if (contentId == null || season == null || episode == null) return null;
  for (final row in episodes) {
    if (row.seriesId == contentId &&
        row.seasonNum == season &&
        row.episodeNum == episode) {
      return row;
    }
  }
  return null;
}

/// Strips a downloaded poster's full image URL back to the TMDB path the
/// synced row stores (e.g. `.../im/w500/abc.jpg` -> `/abc.jpg`). Anything
/// that is not a sized TMDB-style URL yields null: storing a full URL in
/// the row would double-prefix it wherever the row's poster is rendered.
String? tmdbPosterPathFromDownloadUrl(String? posterUrl) {
  if (posterUrl == null) return null;
  const marker = '/w500/';
  final index = posterUrl.indexOf(marker);
  if (index == -1) return null;
  final path = posterUrl.substring(index + marker.length - 1);
  return path.isEmpty ? null : path;
}
