import 'package:flixquest/services/playback_preference_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('audio and quality round-trip for a movie', () async {
    final store = PlaybackPreferenceStore();
    await store.saveAudio(movieId: 42, language: 'en', label: 'English');
    await store.saveQuality(movieId: 42, height: 1080);

    final pref = await store.load(movieId: 42);
    expect(pref, isNotNull);
    expect(pref!.audioLanguage, 'en');
    expect(pref.audioLabel, 'English');
    expect(pref.qualityHeight, 1080);
  });

  test('saving audio keeps a saved quality, and clearing quality keeps audio',
      () async {
    final store = PlaybackPreferenceStore();
    await store.saveQuality(seriesId: 7, height: 720);
    await store.saveAudio(seriesId: 7, language: 'hin', label: 'Hindi');
    var pref = await store.load(seriesId: 7);
    expect(pref!.audioLanguage, 'hin');
    expect(pref.qualityHeight, 720);

    await store.saveQuality(seriesId: 7, height: null);
    pref = await store.load(seriesId: 7);
    expect(pref!.audioLanguage, 'hin');
    expect(pref.qualityHeight, isNull);
  });

  test('movie and series keys do not collide', () async {
    final store = PlaybackPreferenceStore();
    await store.saveAudio(movieId: 9, language: 'en', label: 'English');
    expect(await store.load(seriesId: 9), isNull);
    expect((await store.load(movieId: 9))!.audioLanguage, 'en');
  });

  test('no identity loads nothing and saves nothing', () async {
    final store = PlaybackPreferenceStore();
    expect(await store.load(), isNull);
    await store.saveAudio(language: 'en', label: 'English');
    expect(await store.load(movieId: 1), isNull);
  });

  test('a corrupt entry loads as nothing, not a crash', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PlaybackPreferenceStore.movieKey(5): 'not-json{{{',
    });
    final store = PlaybackPreferenceStore();
    expect(await store.load(movieId: 5), isNull);
  });

  test('preference json round-trips through toJson/fromJson', () {
    const pref = PlaybackPreference(
      audioLanguage: 'de',
      audioLabel: 'Deutsch',
      qualityHeight: 2160,
    );
    final restored = PlaybackPreference.fromJson(pref.toJson());
    expect(restored.audioLanguage, 'de');
    expect(restored.audioLabel, 'Deutsch');
    expect(restored.qualityHeight, 2160);
    expect(const PlaybackPreference().isEmpty, isTrue);
  });
}
