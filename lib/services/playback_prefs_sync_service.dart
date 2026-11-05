import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'playback_preference_store.dart';

/// One title's audio-language pick as it travels in the cloud.
///
/// LANGUAGE ONLY. Quality deliberately stays local-only in this batch:
/// quality is a per-device capability (screen, bandwidth), not a taste,
/// and the local store keeps it beside the audio pick without ever
/// uploading it.
class CloudAudioPref {
  const CloudAudioPref({
    required this.language,
    required this.label,
    required this.updatedAtUtc,
  });

  final String? language;
  final String? label;
  final DateTime updatedAtUtc;

  Map<String, dynamic> toMap() => <String, dynamic>{
        if (language != null) 'audioLanguage': language,
        if (label != null) 'audioLabel': label,
        'updatedAtUtcMs': updatedAtUtc.millisecondsSinceEpoch,
      };

  static CloudAudioPref? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final rawMs = map['updatedAtUtcMs'];
    DateTime? updatedAtUtc;
    if (rawMs is num) {
      updatedAtUtc =
          DateTime.fromMillisecondsSinceEpoch(rawMs.toInt(), isUtc: true);
    } else if (map['updatedAtUtc'] is Timestamp) {
      updatedAtUtc =
          (map['updatedAtUtc'] as Timestamp).toDate().toUtc();
    } else if (map['updatedAtUtc'] is String) {
      updatedAtUtc = DateTime.tryParse(map['updatedAtUtc'] as String);
    }
    if (updatedAtUtc == null) return null;
    return CloudAudioPref(
      language: map['audioLanguage'] as String?,
      label: map['audioLabel'] as String?,
      updatedAtUtc: updatedAtUtc,
    );
  }
}

/// The outcome of merging one title's local audio pick with its cloud
/// pick. Pure data: [PlaybackPrefsSyncService.mergeAudio] computes it
/// with no I/O, so it is unit-tested directly.
class MergedAudioPref {
  const MergedAudioPref({
    required this.language,
    required this.label,
    required this.updatedAtUtc,
    required this.applyToLocal,
    required this.pushToCloud,
  });

  final String? language;
  final String? label;
  final DateTime? updatedAtUtc;

  /// The cloud pick won: write it into the local store (with the
  /// cloud's own stamp, so it does not suddenly look brand new).
  final bool applyToLocal;

  /// The local pick won and the cloud holds something else: push the
  /// local pick up so the other devices learn it.
  final bool pushToCloud;
}

/// The cloud backend behind [PlaybackPrefsSyncService], split out so
/// tests can substitute an in-memory fake instead of Firestore.
abstract class PlaybackPrefsCloudBackend {
  Future<Map<String, dynamic>?> fetchTitle(String uid, String titleKey);
  Future<void> pushTitle(
    String uid,
    String titleKey,
    Map<String, dynamic> data,
  );
}

/// The real backend: one document per title inside the signed-in
/// account's own subcollection. Per-title documents (the wellness-v1
/// pattern) instead of one document holding every title (the
/// named-lists pattern): a pick for one title must never rewrite, or
/// race with, picks for other titles, and player start reads exactly
/// the one title it is about to play.
class FirestorePlaybackPrefsBackend implements PlaybackPrefsCloudBackend {
  FirestorePlaybackPrefsBackend({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore? _firestoreInstance;

  // Lazily resolved so merely constructing the service (a player
  // state field, a test import) never touches Firebase before the app
  // has initialised it; the first real cloud call does.
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? (_firestoreInstance ??= FirebaseFirestore.instance);

  @override
  Future<Map<String, dynamic>?> fetchTitle(String uid, String titleKey) async {
    final doc = await _firestore
        .collection(PlaybackPrefsSyncService.collection)
        .doc(uid)
        .collection(PlaybackPrefsSyncService.titlesCollection)
        .doc(titleKey)
        .get();
    return doc.data();
  }

  @override
  Future<void> pushTitle(
    String uid,
    String titleKey,
    Map<String, dynamic> data,
  ) async {
    await _firestore
        .collection(PlaybackPrefsSyncService.collection)
        .doc(uid)
        .collection(PlaybackPrefsSyncService.titlesCollection)
        .doc(titleKey)
        .set(data, SetOptions(merge: true));
  }
}

/// Syncs per-title audio-language picks across a signed-in user's
/// devices, through a collection that is SEPARATE from the
/// recently-watched rows — deliberately. Progress rows rewrite on
/// every tick, and threading an audio field through them would risk
/// wiping a pick on any save that forgot the field (the same reason
/// [PlaybackPreferenceStore] itself stays separate from those rows).
///
/// Write discipline, same as the local store: the cloud is written
/// ONLY when the viewer picks a language. Player start merges: the
/// newer of the local and cloud pick wins, a cloud pick applies when
/// the device has none, and a tie writes nothing.
///
/// Graceful degradation is the contract, not a fallback: every method
/// here swallows its own errors and returns without throwing, and a
/// signed-out or anonymous user is a no-op. Until the Firestore rules
/// for this collection are published, every cloud call fails and
/// playback carries on exactly as it does today, on local picks only.
class PlaybackPrefsSyncService {
  PlaybackPrefsSyncService({
    PlaybackPrefsCloudBackend? backend,
    String? Function()? uidProvider,
    PlaybackPreferenceStore? localStore,
  })  : _backend = backend ?? FirestorePlaybackPrefsBackend(),
        _uidProvider = uidProvider ??
            (() {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null || user.isAnonymous) return null;
              return user.uid;
            }),
        _localStore = localStore ?? PlaybackPreferenceStore();

  static PlaybackPrefsSyncService? _instance;
  static PlaybackPrefsSyncService get instance =>
      _instance ??= PlaybackPrefsSyncService();

  /// Top-level collection; each account owns one document, named by uid,
  /// whose `titles` subcollection holds one document per title.
  static const String collection = 'playback-prefs-v1';
  static const String titlesCollection = 'titles';

  /// A cloud call that hangs (offline with nothing cached) must never
  /// stall player start: past this, the call is abandoned and the
  /// local pick carries playback, exactly as if sync had failed fast.
  static const Duration _cloudTimeout = Duration(seconds: 8);

  final PlaybackPrefsCloudBackend _backend;
  final String? Function() _uidProvider;
  final PlaybackPreferenceStore _localStore;

  String? get _uid => _uidProvider();
  bool get canSync => _uid != null;

  /// `movie_<tmdbId>` or `series_<seriesId>`; null when the title has
  /// neither id. Movies and series share one namespace on purpose:
  /// the local store already keys them separately, and the prefix
  /// keeps a movie id from colliding with a series id here too.
  static String? titleKey({int? movieId, int? seriesId}) {
    if (movieId != null) return 'movie_$movieId';
    if (seriesId != null) return 'series_$seriesId';
    return null;
  }

  /// Newest pick wins; a missing local stamp (entries written before
  /// sync existed) sorts as the oldest possible pick, so a cloud pick
  /// always beats them. A tie writes nothing either way.
  static MergedAudioPref mergeAudio({
    required PlaybackPreference? local,
    required CloudAudioPref? cloud,
  }) {
    final localHasAudio =
        local != null && (local.audioLanguage != null || local.audioLabel != null);
    if (!localHasAudio && cloud == null) {
      return const MergedAudioPref(
        language: null,
        label: null,
        updatedAtUtc: null,
        applyToLocal: false,
        pushToCloud: false,
      );
    }
    if (!localHasAudio) {
      return MergedAudioPref(
        language: cloud!.language,
        label: cloud.label,
        updatedAtUtc: cloud.updatedAtUtc,
        applyToLocal: true,
        pushToCloud: false,
      );
    }
    if (cloud == null) {
      return MergedAudioPref(
        language: local!.audioLanguage,
        label: local.audioLabel,
        updatedAtUtc: local.audioUpdatedAtUtc,
        applyToLocal: false,
        pushToCloud: true,
      );
    }
    final localAt = local!.audioUpdatedAtUtc ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (cloud.updatedAtUtc.isAfter(localAt)) {
      return MergedAudioPref(
        language: cloud.language,
        label: cloud.label,
        updatedAtUtc: cloud.updatedAtUtc,
        applyToLocal: true,
        pushToCloud: false,
      );
    }
    if (localAt.isAfter(cloud.updatedAtUtc)) {
      return MergedAudioPref(
        language: local.audioLanguage,
        label: local.audioLabel,
        updatedAtUtc: local.audioUpdatedAtUtc,
        applyToLocal: false,
        pushToCloud: true,
      );
    }
    return MergedAudioPref(
      language: local.audioLanguage,
      label: local.audioLabel,
      updatedAtUtc: local.audioUpdatedAtUtc,
      applyToLocal: false,
      pushToCloud: false,
    );
  }

  /// Pushes one viewer pick to the cloud. Called only from the pick
  /// path (never from a restore), with the same stamp the local store
  /// just saved. Never throws; signed out is a no-op.
  Future<void> pushPick({
    int? movieId,
    int? seriesId,
    required String? language,
    required String? label,
    required DateTime updatedAtUtc,
  }) async {
    final uid = _uid;
    final key = titleKey(movieId: movieId, seriesId: seriesId);
    if (uid == null || key == null) return;
    try {
      await _backend
          .pushTitle(
            uid,
            key,
            CloudAudioPref(
              language: language,
              label: label,
              updatedAtUtc: updatedAtUtc,
            ).toMap(),
          )
          .timeout(_cloudTimeout);
    } catch (error) {
      // Rules unpublished, offline, or any other sync failure: the
      // local pick is already saved, so playback is unaffected.
      debugPrint('[PlaybackPrefsSync] push failed (kept local): $error');
    }
  }

  /// Merges the cloud pick for one title into the local store, ahead
  /// of the player's restore step. Never throws; on any failure the
  /// local store is left exactly as it was.
  Future<void> syncAudioOnStart({int? movieId, int? seriesId}) async {
    final uid = _uid;
    final key = titleKey(movieId: movieId, seriesId: seriesId);
    if (uid == null || key == null) return;
    try {
      final local = await _localStore.load(
        movieId: movieId,
        seriesId: seriesId,
      );
      final cloud = CloudAudioPref.fromMap(
        await _backend.fetchTitle(uid, key).timeout(_cloudTimeout),
      );
      final merged = mergeAudio(local: local, cloud: cloud);
      if (merged.applyToLocal) {
        await _localStore.saveAudio(
          movieId: movieId,
          seriesId: seriesId,
          language: merged.language,
          label: merged.label,
          updatedAtUtc: merged.updatedAtUtc,
        );
      } else if (merged.pushToCloud) {
        final stamp = merged.updatedAtUtc ?? DateTime.now().toUtc();
        if (local?.audioUpdatedAtUtc == null) {
          // A stamp-less legacy pick adopts the stamp it is pushed
          // with, so the next merge ties instead of re-pushing.
          await _localStore.saveAudio(
            movieId: movieId,
            seriesId: seriesId,
            language: merged.language,
            label: merged.label,
            updatedAtUtc: stamp,
          );
        }
        await _backend
            .pushTitle(
              uid,
              key,
              CloudAudioPref(
                language: merged.language,
                label: merged.label,
                updatedAtUtc: stamp,
              ).toMap(),
            )
            .timeout(_cloudTimeout);
      }
    } catch (error) {
      // See pushPick: local picks carry playback on their own.
      debugPrint('[PlaybackPrefsSync] start merge failed (kept local): $error');
    }
  }
}
