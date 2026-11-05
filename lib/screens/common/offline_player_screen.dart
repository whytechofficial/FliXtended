import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../functions/language_names.dart';
import '../../functions/offline_resume.dart';
import '../../functions/player_subtitle_configuration.dart';
import '../../models/offline_download.dart';
import '../../models/movie_stream_metadata.dart';
import '../../models/tv_stream_metadata.dart';
import '../../models/wellness.dart';
import '../../constants/app_constants.dart';
import '../../provider/app_dependency_provider.dart';
import '../../provider/recently_watched_provider.dart';
import '../../provider/settings_provider.dart';
import '../../provider/wellness_provider.dart';
import '../../services/streaming_dnd_service.dart';
import 'player/player_feedback_ui.dart';
import 'player/player_strings.dart';
import 'player/player_external_subtitles.dart';

/// The lightweight offline variant of FlixQuest's Better Player. It keeps the
/// same player actions as streaming playback while treating the downloaded
/// quality as a fixed, one-item quality selection.
class OfflinePlayerScreen extends StatefulWidget {
  const OfflinePlayerScreen({
    super.key,
    required this.download,
  });

  final OfflineDownload download;

  @override
  State<OfflinePlayerScreen> createState() => _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState extends State<OfflinePlayerScreen> {
  late final BetterPlayerController _controller;
  final GlobalKey _playerKey = GlobalKey();
  var _initialized = false;
  late final SettingsProvider _settings;

  /// Captured once, not read from context on save: saves also run from
  /// dispose, where the context is going away. Null when the provider is
  /// unavailable, in which case offline playback keeps its local position
  /// only and the synced mirror is skipped, never failed.
  RecentProvider? _recent;
  late final AppDependencyProvider _appDependencies;
  late final StreamingDndSession _streamingDnd;
  int? _occasionalEffectsSuppressionId;
  late final WellnessPlaybackTracker _wellnessTracker;
  late final String _wellnessSessionId;
  bool _completed = false;
  final PlayerExternalSubtitles _externalSubtitles = PlayerExternalSubtitles();

  @override
  void initState() {
    super.initState();
    // Mirror the online/live players: engage Do Not Disturb for the whole
    // downloaded playback (when the setting is on) and release it on dispose.
    // Offline playback has no TV form, so television is always false.
    _streamingDnd = StreamingDndSession(
      Provider.of<SettingsProvider>(context, listen: false),
      television: false,
    );
    final now = DateTime.now();
    _wellnessSessionId =
        '${now.microsecondsSinceEpoch}-offline-${widget.download.id}';
    _wellnessTracker = WellnessPlaybackTracker(
      id: _wellnessSessionId,
      createdAt: now,
    );
    _appDependencies =
        Provider.of<AppDependencyProvider>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _occasionalEffectsSuppressionId != null) return;
      _occasionalEffectsSuppressionId =
          _appDependencies.suppressOccasionalEffects();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final accent = Theme.of(context).primaryColor;
    final settings = context.read<SettingsProvider>();
    _settings = settings;
    try {
      _recent = context.read<RecentProvider>();
    } catch (_) {
      _recent = null;
    }
    final controls = BetterPlayerControlsConfiguration(
      gestureConfiguration: BetterPlayerGestureConfiguration(
        enableVolumeSwipe: true,
        enableBrightnessSwipe: true,
        enableSeekSwipe: true,
        enableDoubleTapSeek: true,
        fastHoldSpeed:
            settings.fastHoldSpeed > 0 ? settings.fastHoldSpeed : null,
        slowHoldSpeed:
            settings.slowHoldSpeed > 0 ? settings.slowHoldSpeed : null,
        volumeSwipeSensitivity: 0.5,
        brightnessSwipeSensitivity: 0.5,
        seekSwipeSensitivity: 1.0,
      ),
      name: widget.download.title,
      subtitle: widget.download.subtitle,
      strings: playerControlsStrings(),
      languageLabelBuilder: languageDisplayName,
      emphasisFontFamily: 'FigtreeSB',
      enableFullscreen: true,
      enableSubtitles: true,
      showSubtitlesButton: true,
      enableQualities: true,
      showQualitiesButton: true,
      enableDownloadButton: true,
      onDownloadTap: _showAlreadyDownloaded,
      enableCrop: true,
      cropIcon: PhosphorIcons.crop(),
      enablePip: true,
      enableAudioTracks: true,
      backgroundColor: Colors.black,
      progressBarBackgroundColor: Colors.white24,
      progressBarHandleColor: accent,
      controlBarColor: Colors.black.withValues(alpha: .48),
      muteIcon: PhosphorIcons.speakerSimpleSlash(),
      unMuteIcon: PhosphorIcons.speakerHigh(),
      pauseIcon: PhosphorIcons.pause(PhosphorIconsStyle.fill),
      pipMenuIcon: PhosphorIcons.pictureInpicture(),
      playIcon: PhosphorIcons.play(PhosphorIconsStyle.fill),
      showControlsOnInitialize: false,
      controlsHideTime: const Duration(milliseconds: 300),
      // White controls; the accent is the timeline's played part alone.
      loadingColor: Colors.white,
      iconsColor: Colors.white,
      progressBarPlayedColor: accent,
      progressBarBufferedColor: Colors.white38,
      skipForwardIcon: PhosphorIcons.arrowClockwise(),
      skipBackIcon: PhosphorIcons.arrowCounterClockwise(),
      fullscreenEnableIcon: PhosphorIcons.cornersOut(),
      fullscreenDisableIcon: PhosphorIcons.cornersIn(),
      overflowMenuIcon: PhosphorIcons.dotsThreeVertical(),
      overflowMenuCustomItems: [
        BetterPlayerOverflowMenuItem(
          PhosphorIcons.closedCaptioning(),
          tr('external_subtitles'),
          _showExternalSubtitles,
        ),
      ],
      controlBarHeight: 56,
    );
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoDetectFullscreenDeviceOrientation: true,
        autoDetectFullscreenAspectRatio: true,
        autoPlay: true,
        fit: BoxFit.contain,
        autoDispose: true,
        allowedScreenSleep: false,
        controlsConfiguration: controls,
        subtitlesConfiguration: buildPlayerSubtitleConfiguration(
          backgroundColor: settings.subtitleBackgroundColor,
          foregroundColor: settings.subtitleForegroundColor,
          fontSize: settings.subtitleFontSize,
          textStyle: settings.subtitleTextStyle,
        ),
        showPlaceholderUntilPlay: true,
        errorBuilder: (_, __) => _OfflinePlaybackError(
          onClose: () => Navigator.pop(context),
        ),
      ),
    );
    _controller.setBetterPlayerGlobalKey(_playerKey);
    _controller.addEventsListener(_onPlayerEvent);
    final savedSubtitle = widget.download.offlineSubtitlePath;
    final quality = widget.download.quality.trim().isEmpty
        ? 'Auto'
        : widget.download.quality.trim();
    final offlineUrl = 'flixquest-offline://${widget.download.id}';
    // Resume where the viewer left off, if a position was saved for this
    // download. The player seeks once initialized; null starts at 0.
    // No local position? Fall back to the title's synced position, so a
    // download watched on another device resumes here too. The local
    // position always wins when it exists: it is the fresher record of
    // what THIS download actually played, and the synced row carries no
    // timestamp to compare it against.
    final localMs = settings.getOfflineResumePosition(widget.download.id);
    int? syncedMs;
    if (localMs == null) {
      try {
        syncedMs = syncedResumeMsForDownload(
          movies: _recent?.movies ?? const [],
          episodes: _recent?.episodes ?? const [],
          download: widget.download,
        );
      } catch (_) {
        syncedMs = null;
      }
    }
    final resumeMs = localMs ?? syncedMs;
    _controller.setupDataSource(
      BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        offlineUrl,
        videoFormat: BetterPlayerVideoFormat.other,
        resolutions: <String, String>{quality: offlineUrl},
        selectedResolution: quality,
        cacheConfiguration: BetterPlayerCacheConfiguration(
          key: 'flixquest-offline:${widget.download.id}',
        ),
        subtitles: savedSubtitle?.isNotEmpty == true
            ? [
                BetterPlayerSubtitlesSource(
                  type: BetterPlayerSubtitlesSourceType.file,
                  urls: [savedSubtitle],
                  name: widget.download.offlineSubtitleName ??
                      'Downloaded subtitle',
                  selectedByDefault: true,
                ),
              ]
            : const [],
      ),
      initialPosition:
          resumeMs != null ? Duration(milliseconds: resumeMs) : null,
    );
  }

  /// Saves the current playback position for this download, so reopening
  /// it resumes where the viewer left off. A finished title (past 85%,
  /// mirroring the streaming rule) clears the saved position instead.
  /// Nothing is touched before the player initializes, so a spurious
  /// early event can never wipe a saved position.
  ///
  /// The position is ALSO mirrored into the title's synced
  /// recently-watched row (see `offline_resume.dart`), which is what makes
  /// the position cross devices. A zero position only clears the local
  /// store: no playback happened, so it must not tombstone a synced row
  /// another device wrote.
  Future<void> _saveResumePosition() async {
    final value = _controller.videoPlayerController?.value;
    if (value == null || !value.initialized) return;
    final positionMs = value.position.inMilliseconds;
    final durationMs = value.duration?.inMilliseconds ?? 0;
    if (positionMs <= 0) {
      await _settings.clearOfflineResumePosition(widget.download.id);
      return;
    }
    if (shouldClearOfflineResume(
      positionMs: positionMs,
      durationMs: durationMs,
    )) {
      await _settings.clearOfflineResumePosition(widget.download.id);
      await _clearSyncedRow();
      return;
    }
    await _settings.setOfflineResumePosition(
      widget.download.id,
      positionMs,
    );
    await _mirrorResumeToSyncedRow(
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }

  /// Mirrors the offline position into the title's synced row. Movies
  /// create the row when streaming never did; episodes do too once the
  /// download record carries an episode id (post-beta64 TV downloads —
  /// see `mirroredEpisodeRow`). Older episode downloads still only
  /// update an existing row. The row's sticky provider is preserved:
  /// offline playback has no provider to record.
  Future<void> _mirrorResumeToSyncedRow({
    required int positionMs,
    required int durationMs,
  }) async {
    final recent = _recent;
    if (recent == null) return;
    final elapsedSeconds = positionMs ~/ 1000;
    if (elapsedSeconds <= 0) return;
    final download = widget.download;
    final durationSeconds = durationMs ~/ 1000;
    if (download.mediaType == 'movie') {
      final movieId = download.contentId;
      if (movieId == null) return;
      final existing =
          existingMovieRow(movies: recent.movies, download: download);
      final remainingSeconds = durationSeconds > 0
          ? (durationSeconds - elapsedSeconds).clamp(0, durationSeconds)
          : (existing?.remaining ?? 0);
      final row = mirroredMovieRow(
        existing: existing,
        movieId: movieId,
        title: download.title,
        posterPath: tmdbPosterPathFromDownloadUrl(download.posterUrl),
        elapsedSeconds: elapsedSeconds,
        remainingSeconds: remainingSeconds,
      );
      if (existing != null && row.id != null) {
        await recent.updateMovie(row, row.id!);
      } else {
        await recent.addMovie(row);
      }
      return;
    }
    final existing =
        existingEpisodeRow(episodes: recent.episodes, download: download);
    final remainingSeconds = durationSeconds > 0
        ? (durationSeconds - elapsedSeconds).clamp(0, durationSeconds)
        : (existing?.remaining ?? 0);
    final row = mirroredEpisodeRow(
      existing: existing,
      elapsedSeconds: elapsedSeconds,
      remainingSeconds: remainingSeconds,
      episodeId: download.episodeId,
      seriesId: download.contentId,
      seasonNum: download.seasonNumber,
      episodeNum: download.episodeNumber,
      // The download record's title is the series name; the episode
      // name itself is not stored cleanly, so a created row carries
      // none until online playback overwrites it with full metadata.
      seriesName: download.title,
      posterPath: tmdbPosterPathFromDownloadUrl(download.posterUrl),
    );
    if (row == null ||
        row.id == null ||
        row.episodeNum == null ||
        row.seasonNum == null) {
      return;
    }
    if (existing != null) {
      await recent.updateEpisode(row, row.id!, row.episodeNum!, row.seasonNum!);
    } else {
      await recent.addEpisode(row);
    }
  }

  /// Drops the title's synced row, mirroring the streaming rule that a
  /// finished title leaves Continue Watching. Tombstoning (not deleting)
  /// is what carries the removal to the other devices.
  Future<void> _clearSyncedRow() async {
    final recent = _recent;
    if (recent == null) return;
    final download = widget.download;
    if (download.mediaType == 'movie') {
      final row = existingMovieRow(movies: recent.movies, download: download);
      if (row?.id != null) await recent.deleteMovie(row!.id!);
      return;
    }
    final row =
        existingEpisodeRow(episodes: recent.episodes, download: download);
    if (row?.id != null &&
        row?.episodeNum != null &&
        row?.seasonNum != null) {
      await recent.deleteEpisode(row!.id!, row.episodeNum!, row.seasonNum!);
    }
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.play:
        _wellnessTracker.play();
      case BetterPlayerEventType.pause:
        _wellnessTracker.pause();
        unawaited(_saveResumePosition());
      case BetterPlayerEventType.bufferingStart:
        _wellnessTracker.pause();
      case BetterPlayerEventType.bufferingEnd:
        if (_controller.videoPlayerController?.value.isPlaying == true) {
          _wellnessTracker.play();
        }
      case BetterPlayerEventType.finished:
        _completed = true;
        _wellnessTracker.pause();
        unawaited(_settings.clearOfflineResumePosition(widget.download.id));
        unawaited(_clearSyncedRow());
        unawaited(_persistWellnessSession(syncImmediately: true));
      default:
        break;
    }
  }

  Future<void> _persistWellnessSession({bool syncImmediately = false}) async {
    final value = _controller.videoPlayerController?.value;
    final isMovie = widget.download.mediaType == 'movie';
    final contentId = isMovie
        ? (widget.download.contentId?.toString() ?? widget.download.id)
        : '${widget.download.contentId ?? 'unknown'}:'
            '${widget.download.seasonNumber ?? 0}:'
            '${widget.download.episodeNumber ?? 0}';
    await WellnessProvider.instance.recordPlayback(
      sessionId: _wellnessSessionId,
      tracker: _wellnessTracker,
      mediaType: isMovie ? WellnessMediaType.movie : WellnessMediaType.episode,
      source: WellnessPlaybackSource.offline,
      contentId: contentId,
      seriesId: isMovie ? null : widget.download.contentId?.toString(),
      title: widget.download.title,
      subtitle: widget.download.subtitle,
      seasonNumber: widget.download.seasonNumber,
      episodeNumber: widget.download.episodeNumber,
      durationMs: value?.duration?.inMilliseconds ?? 0,
      progressEndMs: value?.position.inMilliseconds ?? 0,
      completed: _completed,
      posterPath: widget.download.posterUrl,
      provider: 'Downloaded',
      syncImmediately: syncImmediately,
    );
  }

  void _showAlreadyDownloaded() {
    final quality = widget.download.quality.trim().isEmpty
        ? 'Auto'
        : widget.download.quality.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Already downloaded at $quality.')),
    );
  }

  void _showExternalSubtitles() {
    final id = widget.download.contentId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Subtitle search is unavailable for this older download.')),
      );
      return;
    }
    final isMovie = widget.download.mediaType == 'movie';
    _externalSubtitles.showExternalSubtitlesMenu(
      context: context,
      colors: [
        Theme.of(context).primaryColor,
        Theme.of(context).colorScheme.surface
      ],
      scraperApiUrl: Provider.of<AppDependencyProvider>(context, listen: false)
          .flixquestAPIURL,
      mediaType: isMovie ? MediaType.movie : MediaType.tvShow,
      movieMetadata: isMovie
          ? MovieStreamMetadata(
              backdropPath: null,
              elapsed: 0,
              movieId: id,
              movieName: widget.download.title,
              posterPath: null,
              releaseYear: null,
              isAdult: false,
              releaseDate: null,
            )
          : null,
      tvMetadata: isMovie
          ? null
          : TVStreamMetadata(
              elapsed: 0,
              episodeId: 0,
              episodeName: widget.download.subtitle,
              episodeNumber: widget.download.episodeNumber ?? 0,
              posterPath: null,
              seasonNumber: widget.download.seasonNumber ?? 0,
              seriesName: widget.download.title,
              tvId: id,
              airDate: null,
            ),
      betterPlayerController: _controller,
    );
  }

  @override
  void dispose() {
    if (_initialized) {
      _controller.removeEventsListener(_onPlayerEvent);
      _wellnessTracker.pause();
      // Leaving the player saves the spot; the position is read before
      // the controller is disposed, like the wellness session below.
      unawaited(_saveResumePosition());
      unawaited(_persistWellnessSession(syncImmediately: true));
      _controller.dispose();
    }
    final suppressionId = _occasionalEffectsSuppressionId;
    if (suppressionId != null) {
      _occasionalEffectsSuppressionId = null;
      // Keep effects suppressed through the outgoing route frame. This also
      // overlaps safely with a replacement player's newly acquired scope.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _appDependencies.releaseOccasionalEffectsSuppression(suppressionId);
      });
    }
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _streamingDnd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: BetterPlayer(controller: _controller, key: _playerKey),
        ),
      ),
    );
  }
}

/// What shows when a download won't play: the main player's error look over
/// the black video area, with a way back to Downloads, since switching
/// provider or retrying can't help a file on the device.
class _OfflinePlaybackError extends StatelessWidget {
  const _OfflinePlaybackError({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => PlayerErrorView(
        title: tr('offline_play_failed'),
        message: tr('offline_play_failed_hint'),
        icon: PhosphorIcons.fileX(),
        actions: [
          PlayerActionButton(
            label: tr('go_back'),
            icon: PhosphorIcons.arrowLeft(),
            primary: true,
            onPressed: onClose,
          ),
        ],
      );
}
