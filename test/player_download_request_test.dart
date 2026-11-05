import 'package:flixquest/models/movie_stream_metadata.dart';
import 'package:flixquest/models/tv_stream_metadata.dart';
import 'package:flixquest/screens/common/player.dart';
import 'package:flutter_test/flutter_test.dart';

/// Beta65: the phone player's in-player download is the only phone-side
/// episode enqueue site. The movie loader (`movie_video_loader.dart`) is
/// movie-only — there is no episode to pass there — and the series
/// details download button opens the player with `download: true`, so it
/// funnels into the same `_downloadFromCurrentProvider` path. These
/// tests pin the request builder extracted from that method: an episode
/// download must carry the TMDB episode id (what lets an offline-first
/// episode key a synced resume row via `mirroredEpisodeRow`), a movie
/// download must not, and metadata without an episode id must fall back
/// to null rather than crash.

TVStreamMetadata episodeMetadata({int? episodeId}) => TVStreamMetadata(
      elapsed: 0,
      episodeId: episodeId,
      episodeName: 'Pilot',
      episodeNumber: 1,
      posterPath: '/poster.jpg',
      seasonNumber: 1,
      seriesName: 'Breaking Bad',
      tvId: 1396,
      airDate: '2008-01-20',
    );

MovieStreamMetadata movieMetadata() => MovieStreamMetadata(
      backdropPath: '/backdrop.jpg',
      elapsed: 0,
      movieId: 550,
      movieName: 'Fight Club',
      posterPath: '/poster.jpg',
      releaseYear: 1999,
      isAdult: false,
      releaseDate: '1999-10-15',
    );

void main() {
  group('buildPlayerDownloadRequest', () {
    test('episode download carries the TMDB episode id', () {
      final request = buildPlayerDownloadRequest(
        url: 'https://example.test/master.m3u8',
        format: 'hls',
        quality: '720p',
        isMovie: false,
        movie: null,
        episode: episodeMetadata(episodeId: 62085),
        season: 1,
        episodeNumber: 1,
        posterPath: '/poster.jpg',
        maxVideoHeight: 720,
        headers: const {},
        audioTrack: null,
        subtitleTrackUrl: null,
        subtitleTrackName: null,
        subtitleTrackHeaders: const {},
        providerName: 'Provider',
      );

      expect(request.mediaType, 'episode');
      expect(request.id, 'tv_1396_s1_e1');
      expect(request.contentId, 1396);
      expect(request.seasonNumber, 1);
      expect(request.episodeNumber, 1);
      expect(request.episodeId, 62085);
      // The id survives the store round-trip, like the beta64 TV path.
      expect(request.toMap()['episodeId'], 62085);
    });

    test('movie download carries no episode id', () {
      final request = buildPlayerDownloadRequest(
        url: 'https://example.test/movie.mp4',
        format: 'progressive',
        quality: '720p',
        isMovie: true,
        movie: movieMetadata(),
        episode: null,
        season: 0,
        episodeNumber: 0,
        posterPath: '/poster.jpg',
        maxVideoHeight: 720,
        headers: const {},
        audioTrack: null,
        subtitleTrackUrl: null,
        subtitleTrackName: null,
        subtitleTrackHeaders: const {},
        providerName: 'Provider',
      );

      expect(request.mediaType, 'movie');
      expect(request.id, 'movie_550');
      expect(request.contentId, 550);
      expect(request.episodeId, isNull);
    });

    test('episode metadata without an episode id falls back to null', () {
      final request = buildPlayerDownloadRequest(
        url: 'https://example.test/master.m3u8',
        format: 'hls',
        quality: '720p',
        isMovie: false,
        movie: null,
        episode: episodeMetadata(),
        season: 1,
        episodeNumber: 1,
        posterPath: '/poster.jpg',
        maxVideoHeight: 720,
        headers: const {},
        audioTrack: null,
        subtitleTrackUrl: null,
        subtitleTrackName: null,
        subtitleTrackHeaders: const {},
        providerName: 'Provider',
      );

      // No crash, no invented id: the download simply cannot key a
      // synced row, exactly like a pre-beta64 download.
      expect(request.episodeId, isNull);
      expect(request.mediaType, 'episode');
    });
  });
}
