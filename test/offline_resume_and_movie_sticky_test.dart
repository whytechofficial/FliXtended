import 'package:flixquest/constants/app_constants.dart';
import 'package:flixquest/functions/offline_resume.dart';
import 'package:flixquest/preferences/setting_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sharedPrefsSingleton = await SharedPreferences.getInstance();
    prefs = SettingsPreferences();
  });

  group('movie sticky provider', () {
    test('round-trips per movie id', () async {
      expect(prefs.getLastMovieProvider(123), isNull);
      await prefs.setLastMovieProvider(123, 'direct:netmirror');
      expect(prefs.getLastMovieProvider(123), 'direct:netmirror');
      // Other movies are independent.
      expect(prefs.getLastMovieProvider(456), isNull);
      await prefs.setLastMovieProvider(123, 'zeila');
      expect(prefs.getLastMovieProvider(123), 'zeila');
    });

    test('movie keys do not collide with TV keys', () async {
      await prefs.setLastTvProvider(123, 'direct:netmirror');
      expect(prefs.getLastMovieProvider(123), isNull);
      await prefs.setLastMovieProvider(123, 'zeila');
      expect(prefs.getLastTvProvider(123), 'direct:netmirror');
    });
  });

  group('offline resume position', () {
    test('round-trips per download id and clears', () async {
      expect(prefs.getOfflineResumePosition('dl-1'), isNull);
      await prefs.setOfflineResumePosition('dl-1', 123456);
      expect(prefs.getOfflineResumePosition('dl-1'), 123456);
      expect(prefs.getOfflineResumePosition('dl-2'), isNull);
      await prefs.clearOfflineResumePosition('dl-1');
      expect(prefs.getOfflineResumePosition('dl-1'), isNull);
    });

    test('non-positive positions are never resumed', () async {
      await prefs.setOfflineResumePosition('dl-1', 0);
      expect(prefs.getOfflineResumePosition('dl-1'), isNull);
    });
  });

  group('shouldClearOfflineResume', () {
    test('clears only past 85%, mirroring the streaming rule', () {
      expect(
        shouldClearOfflineResume(positionMs: 86000, durationMs: 100000),
        isTrue,
      );
      expect(
        shouldClearOfflineResume(positionMs: 85000, durationMs: 100000),
        isFalse,
      );
      expect(
        shouldClearOfflineResume(positionMs: 50000, durationMs: 100000),
        isFalse,
      );
      // An unknown duration can never clear a position.
      expect(
        shouldClearOfflineResume(positionMs: 50000, durationMs: 0),
        isFalse,
      );
      expect(
        shouldClearOfflineResume(positionMs: 0, durationMs: 100000),
        isFalse,
      );
    });
  });
}
