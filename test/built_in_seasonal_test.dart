import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flixquest/models/occasional_theme.dart';

void main() {
  group('built-in seasonal catalog', () {
    test('it is on, selectable, and animated', () {
      final catalog = OccasionalThemeCatalog.builtIn(
        now: DateTime.utc(2026, 11, 2),
      );
      expect(catalog.enabled, isTrue);
      expect(catalog.allowUserSelection, isTrue);
      expect(catalog.effectsEnabled, isTrue);
      expect(catalog.allowUserEffectsToggle, isTrue);
      // Every season survived construction: a misspelled id would land
      // here disabled instead of being dropped silently.
      expect(
        catalog.themes.map((theme) => theme.id),
        containsAll(<String>[
          'halloween',
          'christmas',
          'new_year',
          'valentines',
          'spring',
          'ethiopian_new_year',
        ]),
      );
      expect(catalog.themes.every((theme) => theme.enabled), isTrue);
    });

    test('Halloween is the season right now, with bats', () {
      final catalog = OccasionalThemeCatalog.builtIn(
        now: DateTime.utc(2026, 11, 2),
      );
      final active = catalog.resolve(
        selectedThemeId: 'automatic',
        now: DateTime.utc(2026, 11, 2),
      );
      expect(active?.id, 'halloween');
      expect(active?.primaryColor, const Color(0xFFFF6D00));
      expect(active?.effect.enabled, isTrue);
      expect(active?.effect.type, OccasionalEffectType.bats);
    });

    test('each fixed season is active on its own day', () {
      OccasionalTheme? activeOn(DateTime day) =>
          OccasionalThemeCatalog.builtIn(now: day).resolve(
            selectedThemeId: 'automatic',
            now: day,
          );

      expect(activeOn(DateTime.utc(2026, 12, 25))?.id, 'christmas');
      expect(
        activeOn(DateTime.utc(2026, 12, 25))?.effect.type,
        OccasionalEffectType.snow,
      );
      expect(activeOn(DateTime.utc(2027, 1, 1))?.id, 'new_year');
      expect(
        activeOn(DateTime.utc(2027, 1, 1))?.effect.type,
        OccasionalEffectType.fireworks,
      );
      expect(activeOn(DateTime.utc(2026, 2, 14))?.id, 'valentines');
      expect(
        activeOn(DateTime.utc(2026, 2, 14))?.effect.type,
        OccasionalEffectType.hearts,
      );
      expect(activeOn(DateTime.utc(2026, 4, 15))?.id, 'spring');
      expect(
        activeOn(DateTime.utc(2026, 4, 15))?.effect.type,
        OccasionalEffectType.petals,
      );
      expect(activeOn(DateTime.utc(2026, 9, 11))?.id, 'ethiopian_new_year');
      expect(
        activeOn(DateTime.utc(2026, 9, 11))?.effect.type,
        OccasionalEffectType.adeyFlowers,
      );
    });

    test('the New Year window spans the year boundary both ways', () {
      final december = OccasionalThemeCatalog.builtIn(
        now: DateTime.utc(2026, 12, 30),
      );
      expect(
        december.resolve(
          selectedThemeId: 'automatic',
          now: DateTime.utc(2026, 12, 30),
        )?.id,
        'new_year',
      );
      final january = OccasionalThemeCatalog.builtIn(
        now: DateTime.utc(2027, 1, 2),
      );
      final theme = january.themes.firstWhere(
        (theme) => theme.id == 'new_year',
      );
      expect(theme.startsAt, DateTime.utc(2026, 12, 28));
      expect(theme.endsAt, DateTime.utc(2027, 1, 3, 23, 59, 59));
      expect(
        january.resolve(
          selectedThemeId: 'automatic',
          now: DateTime.utc(2027, 1, 2),
        )?.id,
        'new_year',
      );
    });

    test('past the New Year window, the next one is next December', () {
      final catalog = OccasionalThemeCatalog.builtIn(
        now: DateTime.utc(2027, 1, 5),
      );
      final theme = catalog.themes.firstWhere(
        (theme) => theme.id == 'new_year',
      );
      expect(theme.startsAt, DateTime.utc(2027, 12, 28));
      expect(
        catalog.resolve(
          selectedThemeId: 'automatic',
          now: DateTime.utc(2027, 1, 5),
        ),
        isNull,
      );
    });

    test('a gap between seasons resolves to nothing', () {
      final catalog = OccasionalThemeCatalog.builtIn(
        now: DateTime.utc(2026, 6, 15),
      );
      expect(
        catalog.resolve(
          selectedThemeId: 'automatic',
          now: DateTime.utc(2026, 6, 15),
        ),
        isNull,
      );
    });

    test('an explicit season pick wins over automatic', () {
      final catalog = OccasionalThemeCatalog.builtIn(
        now: DateTime.utc(2026, 11, 2),
      );
      expect(
        catalog.resolve(
          selectedThemeId: 'halloween',
          now: DateTime.utc(2026, 11, 2),
        )?.id,
        'halloween',
      );
    });

    test('fallback keeps an enabled remote catalog, fills a disabled one', () {
      final remote = OccasionalThemeCatalog.fromJsonString(
        '{"enabled":true,"allow_user_selection":true,"themes":['
        '{"id":"christmas","enabled":true,'
        '"starts_at":"2026-12-01T00:00:00.000Z",'
        '"ends_at":"2026-12-27T23:59:59.000Z"}]}',
      );
      expect(
        OccasionalThemeCatalog.withBuiltInFallback(remote),
        same(remote),
      );

      final filled = OccasionalThemeCatalog.withBuiltInFallback(
        const OccasionalThemeCatalog.disabled(),
        now: DateTime.utc(2026, 11, 2),
      );
      expect(filled.enabled, isTrue);
      expect(
        filled.resolve(
          selectedThemeId: 'automatic',
          now: DateTime.utc(2026, 11, 2),
        )?.id,
        'halloween',
      );
    });
  });
}
