import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The audio language and quality height a viewer picked for one title, kept
/// across sessions so resuming restores the pick instead of the stream
/// default.
///
/// Keys are the title's own identity, not the provider: a movie is keyed by
/// its TMDB id, a series by its series id, so one choice covers every
/// episode of a show. Values are matched by language/height on restore and
/// ignored when the stream no longer offers them, so a stale choice can
/// never break playback.
///
/// This store is deliberately separate from the recently-watched progress
/// rows: progress saves rewrite those rows on every tick, and threading
/// audio/quality through them would risk wiping a pick on any save that
/// forgot the fields. These preferences are written only when the viewer
/// picks something, and read only when a player starts.
class PlaybackPreference {
  const PlaybackPreference({
    this.audioLanguage,
    this.audioLabel,
    this.qualityHeight,
    this.audioUpdatedAtUtc,
  });

  /// The picked audio track's language code (for example "en", "hin").
  final String? audioLanguage;

  /// The picked audio track's label, kept as a fallback match when the
  /// language code alone does not identify a track.
  final String? audioLabel;

  /// When the audio pick was made, in UTC. This is what orders a pick
  /// against the cloud copy in cross-device sync: the newer pick wins.
  /// Entries written before sync existed carry null and sort as the
  /// oldest possible pick, so a cloud pick always beats them.
  final DateTime? audioUpdatedAtUtc;

  /// The picked quality height in pixels (for example 1080). Null means
  /// no per-title pick: the stream default (or the global preference)
  /// applies.
  final int? qualityHeight;

  bool get isEmpty =>
      audioLanguage == null && audioLabel == null && qualityHeight == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (audioLanguage != null) 'audioLanguage': audioLanguage,
        if (audioLabel != null) 'audioLabel': audioLabel,
        if (qualityHeight != null) 'qualityHeight': qualityHeight,
        if (audioUpdatedAtUtc != null)
          'audioUpdatedAtUtcMs': audioUpdatedAtUtc!.millisecondsSinceEpoch,
      };

  factory PlaybackPreference.fromJson(Map<String, dynamic> json) {
    DateTime? audioUpdatedAtUtc;
    final rawMs = json['audioUpdatedAtUtcMs'];
    if (rawMs is num) {
      audioUpdatedAtUtc =
          DateTime.fromMillisecondsSinceEpoch(rawMs.toInt(), isUtc: true);
    } else if (json['audioUpdatedAtUtc'] is String) {
      audioUpdatedAtUtc =
          DateTime.tryParse(json['audioUpdatedAtUtc'] as String);
    }
    return PlaybackPreference(
      audioLanguage: json['audioLanguage'] as String?,
      audioLabel: json['audioLabel'] as String?,
      qualityHeight: (json['qualityHeight'] as num?)?.toInt(),
      audioUpdatedAtUtc: audioUpdatedAtUtc,
    );
  }
}

class PlaybackPreferenceStore {
  PlaybackPreferenceStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  static String movieKey(int movieId) => 'playback_pref_movie_$movieId';

  static String seriesKey(int seriesId) => 'playback_pref_series_$seriesId';

  static String? _key({int? movieId, int? seriesId}) {
    if (movieId != null) return movieKey(movieId);
    if (seriesId != null) return seriesKey(seriesId);
    return null;
  }

  Future<PlaybackPreference?> load({int? movieId, int? seriesId}) async {
    final key = _key(movieId: movieId, seriesId: seriesId);
    if (key == null) return null;
    final prefs = await _preferences();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return PlaybackPreference.fromJson(decoded);
    } catch (_) {
      // A corrupt entry must never break playback: forget it.
      return null;
    }
  }

  /// Records an audio pick, keeping any saved quality pick untouched.
  /// [updatedAtUtc] defaults to now: callers restoring a pick from
  /// elsewhere (cloud sync) pass that pick's own stamp so the restored
  /// value does not suddenly look newer than the pick it came from.
  Future<void> saveAudio({
    int? movieId,
    int? seriesId,
    required String? language,
    required String? label,
    DateTime? updatedAtUtc,
  }) async {
    final key = _key(movieId: movieId, seriesId: seriesId);
    if (key == null) return;
    final current = await load(movieId: movieId, seriesId: seriesId);
    await _write(
      key,
      PlaybackPreference(
        audioLanguage: language,
        audioLabel: label,
        qualityHeight: current?.qualityHeight,
        audioUpdatedAtUtc: updatedAtUtc ?? DateTime.now().toUtc(),
      ),
    );
  }

  /// Records a quality pick, keeping any saved audio pick untouched.
  /// A null height clears the quality pick (the viewer chose Automatic),
  /// so later resumes use the stream default again.
  Future<void> saveQuality({
    int? movieId,
    int? seriesId,
    required int? height,
  }) async {
    final key = _key(movieId: movieId, seriesId: seriesId);
    if (key == null) return;
    final current = await load(movieId: movieId, seriesId: seriesId);
    await _write(
      key,
      PlaybackPreference(
        audioLanguage: current?.audioLanguage,
        audioLabel: current?.audioLabel,
        qualityHeight: height,
        audioUpdatedAtUtc: current?.audioUpdatedAtUtc,
      ),
    );
  }

  Future<void> _write(String key, PlaybackPreference pref) async {
    final prefs = await _preferences();
    if (pref.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, jsonEncode(pref.toJson()));
  }
}
