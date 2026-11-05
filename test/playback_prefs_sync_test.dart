import 'package:flixquest/services/playback_preference_store.dart';
import 'package:flixquest/services/playback_prefs_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime _at(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

PlaybackPreference _local(
  String? language,
  String? label,
  int? updatedAtMs,
) =>
    PlaybackPreference(
      audioLanguage: language,
      audioLabel: label,
      audioUpdatedAtUtc: updatedAtMs == null ? null : _at(updatedAtMs),
    );

CloudAudioPref _cloud(String? language, String? label, int updatedAtMs) =>
    CloudAudioPref(
      language: language,
      label: label,
      updatedAtUtc: _at(updatedAtMs),
    );

/// In-memory stand-in for Firestore: keyed by "$uid/$titleKey", with a
/// switch to fail every call the way an unpublished-rules or offline
/// backend would.
class _FakeBackend implements PlaybackPrefsCloudBackend {
  final Map<String, Map<String, dynamic>> docs = {};
  bool fail = false;

  @override
  Future<Map<String, dynamic>?> fetchTitle(
    String uid,
    String titleKey,
  ) async {
    if (fail) throw StateError('offline');
    return docs['$uid/$titleKey'];
  }

  @override
  Future<void> pushTitle(
    String uid,
    String titleKey,
    Map<String, dynamic> data,
  ) async {
    if (fail) throw StateError('offline');
    docs['$uid/$titleKey'] = Map<String, dynamic>.from(data);
  }
}

PlaybackPrefsSyncService _service(
  _FakeBackend backend, {
  String? uid = 'uid-1',
}) =>
    PlaybackPrefsSyncService(
      backend: backend,
      uidProvider: () => uid,
      localStore: PlaybackPreferenceStore(),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('mergeAudio (pure)', () {
    test('cloud-newer wins and applies to local', () {
      final merged = PlaybackPrefsSyncService.mergeAudio(
        local: _local('hin', 'Hindi', 1000),
        cloud: _cloud('tam', 'Tamil', 2000),
      );
      expect(merged.language, 'tam');
      expect(merged.applyToLocal, isTrue);
      expect(merged.pushToCloud, isFalse);
    });

    test('local-newer wins and pushes to cloud', () {
      final merged = PlaybackPrefsSyncService.mergeAudio(
        local: _local('tam', 'Tamil', 3000),
        cloud: _cloud('hin', 'Hindi', 2000),
      );
      expect(merged.language, 'tam');
      expect(merged.applyToLocal, isFalse);
      expect(merged.pushToCloud, isTrue);
    });

    test('cloud-only applies when local has none', () {
      final merged = PlaybackPrefsSyncService.mergeAudio(
        local: null,
        cloud: _cloud('tam', 'Tamil', 2000),
      );
      expect(merged.language, 'tam');
      expect(merged.applyToLocal, isTrue);
      expect(merged.pushToCloud, isFalse);
    });

    test('local-only pushes to cloud', () {
      final merged = PlaybackPrefsSyncService.mergeAudio(
        local: _local('tam', 'Tamil', 1000),
        cloud: null,
      );
      expect(merged.language, 'tam');
      expect(merged.applyToLocal, isFalse);
      expect(merged.pushToCloud, isTrue);
    });

    test('a tie writes nothing either way', () {
      final merged = PlaybackPrefsSyncService.mergeAudio(
        local: _local('tam', 'Tamil', 2000),
        cloud: _cloud('tam', 'Tamil', 2000),
      );
      expect(merged.applyToLocal, isFalse);
      expect(merged.pushToCloud, isFalse);
    });

    test('a stamp-less legacy local pick loses to any cloud pick', () {
      final merged = PlaybackPrefsSyncService.mergeAudio(
        local: _local('hin', 'Hindi', null),
        cloud: _cloud('tam', 'Tamil', 2000),
      );
      expect(merged.language, 'tam');
      expect(merged.applyToLocal, isTrue);
    });

    test('neither side having a pick merges to nothing', () {
      final merged = PlaybackPrefsSyncService.mergeAudio(
        local: null,
        cloud: null,
      );
      expect(merged.language, isNull);
      expect(merged.applyToLocal, isFalse);
      expect(merged.pushToCloud, isFalse);
    });
  });

  group('CloudAudioPref record', () {
    test('round-trips through toMap/fromMap', () {
      final record = _cloud('tam', 'Tamil', 2000);
      final restored = CloudAudioPref.fromMap(record.toMap());
      expect(restored, isNotNull);
      expect(restored!.language, 'tam');
      expect(restored.label, 'Tamil');
      expect(restored.updatedAtUtc, _at(2000));
    });

    test('a map without a stamp is not a pick', () {
      expect(
        CloudAudioPref.fromMap(<String, dynamic>{'audioLanguage': 'tam'}),
        isNull,
      );
    });
  });

  group('syncAudioOnStart (fake backend)', () {
    test('cloud-newer pick lands in the local store', () async {
      final backend = _FakeBackend();
      final service = _service(backend);
      final store = PlaybackPreferenceStore();
      await store.saveAudio(
        movieId: 550,
        language: 'hin',
        label: 'Hindi',
        updatedAtUtc: _at(1000),
      );
      backend.docs['uid-1/movie_550'] =
          _cloud('tam', 'Tamil', 2000).toMap();

      await service.syncAudioOnStart(movieId: 550);

      final pref = await store.load(movieId: 550);
      expect(pref!.audioLanguage, 'tam');
      expect(pref.audioLabel, 'Tamil');
      expect(pref.audioUpdatedAtUtc, _at(2000));
      // Quality beside it is untouched by the audio-only merge.
      expect(pref.qualityHeight, isNull);
    });

    test('cloud-only pick applies and preserves a local quality pick',
        () async {
      final backend = _FakeBackend();
      final service = _service(backend);
      final store = PlaybackPreferenceStore();
      await store.saveQuality(movieId: 550, height: 1080);
      backend.docs['uid-1/movie_550'] =
          _cloud('tam', 'Tamil', 2000).toMap();

      await service.syncAudioOnStart(movieId: 550);

      final pref = await store.load(movieId: 550);
      expect(pref!.audioLanguage, 'tam');
      expect(pref.qualityHeight, 1080);
    });

    test('local-newer pick pushes to cloud and leaves local alone',
        () async {
      final backend = _FakeBackend();
      final service = _service(backend);
      final store = PlaybackPreferenceStore();
      await store.saveAudio(
        seriesId: 1399,
        language: 'tam',
        label: 'Tamil',
        updatedAtUtc: _at(3000),
      );
      backend.docs['uid-1/series_1399'] =
          _cloud('hin', 'Hindi', 2000).toMap();

      await service.syncAudioOnStart(seriesId: 1399);

      final pushed =
          CloudAudioPref.fromMap(backend.docs['uid-1/series_1399']);
      expect(pushed!.language, 'tam');
      expect(pushed.updatedAtUtc, _at(3000));
      expect((await store.load(seriesId: 1399))!.audioLanguage, 'tam');
    });

    test('signed out is a no-op: no read, no write', () async {
      final backend = _FakeBackend();
      final service = _service(backend, uid: null);
      final store = PlaybackPreferenceStore();
      await store.saveAudio(movieId: 550, language: 'hin', label: 'Hindi');
      backend.docs['uid-1/movie_550'] =
          _cloud('tam', 'Tamil', 2000).toMap();

      await service.syncAudioOnStart(movieId: 550);

      expect((await store.load(movieId: 550))!.audioLanguage, 'hin');
    });
  });

  group('pushPick (fake backend)', () {
    test('a pick lands in the cloud with its stamp', () async {
      final backend = _FakeBackend();
      final service = _service(backend);

      await service.pushPick(
        movieId: 550,
        language: 'tam',
        label: 'Tamil',
        updatedAtUtc: _at(4000),
      );

      final pushed = CloudAudioPref.fromMap(backend.docs['uid-1/movie_550']);
      expect(pushed!.language, 'tam');
      expect(pushed.updatedAtUtc, _at(4000));
    });
  });

  group('graceful degradation', () {
    test('a failing backend leaves local picks untouched and never throws',
        () async {
      final backend = _FakeBackend()..fail = true;
      final service = _service(backend);
      final store = PlaybackPreferenceStore();
      await store.saveAudio(movieId: 550, language: 'hin', label: 'Hindi');

      await service.syncAudioOnStart(movieId: 550);
      await service.pushPick(
        movieId: 550,
        language: 'tam',
        label: 'Tamil',
        updatedAtUtc: _at(4000),
      );

      expect((await store.load(movieId: 550))!.audioLanguage, 'hin');
      expect(backend.docs, isEmpty);
    });
  });

  group('titleKey', () {
    test('movies and series do not collide', () {
      expect(
        PlaybackPrefsSyncService.titleKey(movieId: 7),
        isNot(PlaybackPrefsSyncService.titleKey(seriesId: 7)),
      );
      expect(PlaybackPrefsSyncService.titleKey(), isNull);
    });
  });
}
