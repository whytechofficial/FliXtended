import 'package:flixquest/functions/offline_resume.dart';
import 'package:flixquest/models/offline_download.dart';
import 'package:flixquest/models/recently_watched.dart';
import 'package:flutter_test/flutter_test.dart';

/// Item 9: the offline player's position is keyed by title in the synced
/// record, not by the device-local download id. These tests pin the pure
/// rules the offline screen applies: fallback lookup, mirrored rows, and
/// the poster-path conversion. The screen itself (local-wins precedence,
/// 85% tombstoning) is covered by the comments in
/// offline_player_screen.dart; its BetterPlayer surface is not unit
/// testable here.

OfflineDownload download({
  required String id,
  required String mediaType,
  int? contentId,
  int? seasonNumber,
  int? episodeNumber,
  String? posterUrl,
}) =>
    OfflineDownload(
      id: id,
      title: 'Title',
      mediaType: mediaType,
      quality: 'Auto',
      state: OfflineDownloadState.completed,
      progress: 100,
      bytesDownloaded: 100,
      contentLength: 100,
      createdAt: DateTime(2026, 11, 5),
      contentId: contentId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      posterUrl: posterUrl,
    );

RecentMovie movieRow({int elapsed = 6360}) => RecentMovie(
      backdropPath: '/backdrop.jpg',
      dateTime: '2026-11-05 02:00:00.000',
      elapsed: elapsed,
      id: 550,
      posterPath: '/poster.jpg',
      releaseYear: 1999,
      remaining: 1200,
      title: 'Fight Club',
      providerCode: 'scraper:aethoflix',
    );

RecentEpisode episodeRow({int elapsed = 900}) => RecentEpisode(
      dateTime: '2026-11-05 02:00:00.000',
      elapsed: elapsed,
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

void main() {
  group('syncedResumeMsForDownload', () {
    test('movie fallback is the synced elapsed, in milliseconds', () {
      expect(
        syncedResumeMsForDownload(
          movies: [movieRow()],
          episodes: const [],
          download: download(id: 'movie_550', mediaType: 'movie',
              contentId: 550),
        ),
        6360 * 1000,
      );
    });

    test('episode fallback matches series + season + episode, not id', () {
      expect(
        syncedResumeMsForDownload(
          movies: const [],
          episodes: [episodeRow()],
          download: download(
            id: 'tv_1396_s1_e1',
            mediaType: 'episode',
            contentId: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
          ),
        ),
        900 * 1000,
      );
      // A different episode of the same series is not this download.
      expect(
        syncedResumeMsForDownload(
          movies: const [],
          episodes: [episodeRow()],
          download: download(
            id: 'tv_1396_s1_e2',
            mediaType: 'episode',
            contentId: 1396,
            seasonNumber: 1,
            episodeNumber: 2,
          ),
        ),
        isNull,
      );
    });

    test('no row, no content id, or zero elapsed means no fallback', () {
      expect(
        syncedResumeMsForDownload(
          movies: const [],
          episodes: const [],
          download: download(id: 'movie_550', mediaType: 'movie',
              contentId: 550),
        ),
        isNull,
      );
      expect(
        syncedResumeMsForDownload(
          movies: [movieRow()],
          episodes: const [],
          download: download(id: 'old', mediaType: 'movie'),
        ),
        isNull,
      );
      expect(
        syncedResumeMsForDownload(
          movies: [movieRow(elapsed: 0)],
          episodes: const [],
          download: download(id: 'movie_550', mediaType: 'movie',
              contentId: 550),
        ),
        isNull,
      );
    });
  });

  group('mirrored rows', () {
    test('movie mirror keeps the existing row display fields + sticky', () {
      final row = mirroredMovieRow(
        existing: movieRow(),
        movieId: 550,
        title: 'Other title',
        posterPath: '/other.jpg',
        elapsedSeconds: 7000,
        remainingSeconds: 500,
      );

      expect(row.id, 550);
      expect(row.title, 'Fight Club');
      expect(row.posterPath, '/poster.jpg');
      expect(row.backdropPath, '/backdrop.jpg');
      expect(row.releaseYear, 1999);
      expect(row.providerCode, 'scraper:aethoflix');
      expect(row.elapsed, 7000);
      expect(row.remaining, 500);
      expect(row.synced, isFalse);
    });

    test('movie mirror creates a minimal row when never streamed', () {
      final row = mirroredMovieRow(
        existing: null,
        movieId: 550,
        title: 'Fight Club',
        posterPath: '/poster.jpg',
        elapsedSeconds: 6360,
        remainingSeconds: 1200,
      );

      expect(row.id, 550);
      expect(row.title, 'Fight Club');
      expect(row.posterPath, '/poster.jpg');
      expect(row.providerCode, isNull);
      expect(row.elapsed, 6360);
    });

    test('episode mirror updates an existing row and keeps its sticky', () {
      final row = mirroredEpisodeRow(
        existing: episodeRow(),
        elapsedSeconds: 1000,
        remainingSeconds: 1100,
      );

      expect(row?.id, 62085);
      expect(row?.seriesId, 1396);
      expect(row?.providerCode, 'scraper:aethoflix');
      expect(row?.elapsed, 1000);
    });

    test('episode mirror creates nothing without an existing row', () {
      // A download record with no episode id has nothing to key a new
      // row by (everything enqueued before beta64).
      expect(
        mirroredEpisodeRow(
          existing: null,
          elapsedSeconds: 1000,
          remainingSeconds: 1100,
        ),
        isNull,
      );
    });

    test('episode mirror creates a minimal row with an episode id', () {
      // Post-beta64 download records carry the episode id, so an
      // offline-first episode can key a new row, like the movie mirror.
      final row = mirroredEpisodeRow(
        existing: null,
        elapsedSeconds: 1000,
        remainingSeconds: 1100,
        episodeId: 62085,
        seriesId: 1396,
        seasonNum: 1,
        episodeNum: 1,
        seriesName: 'Series 1396',
        posterPath: '/p.jpg',
      );

      expect(row?.id, 62085);
      expect(row?.seriesId, 1396);
      expect(row?.seasonNum, 1);
      expect(row?.episodeNum, 1);
      expect(row?.seriesName, 'Series 1396');
      expect(row?.elapsed, 1000);
      expect(row?.synced, isFalse);
    });

    test('existing-row lookup finds the movie and the episode', () {
      expect(
        existingMovieRow(
          movies: [movieRow()],
          download: download(id: 'movie_550', mediaType: 'movie',
              contentId: 550),
        )?.id,
        550,
      );
      expect(
        existingEpisodeRow(
          episodes: [episodeRow()],
          download: download(
            id: 'tv_1396_s1_e1',
            mediaType: 'episode',
            contentId: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
          ),
        )?.id,
        62085,
      );
    });
  });

  group('tmdbPosterPathFromDownloadUrl', () {
    test('strips a sized image URL back to its TMDB path', () {
      expect(
        tmdbPosterPathFromDownloadUrl(
          'https://jiofix.aadilsamjeed.workers.dev/im/w500/abc.jpg',
        ),
        '/abc.jpg',
      );
    });

    test('anything else yields null, never a full URL in the row', () {
      expect(tmdbPosterPathFromDownloadUrl(null), isNull);
      expect(
        tmdbPosterPathFromDownloadUrl('https://example.com/poster.jpg'),
        isNull,
      );
    });
  });
}
