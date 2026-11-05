import 'package:flixquest/constants/app_constants.dart';
import 'package:flixquest/preferences/setting_preferences.dart';
import 'package:flixquest/provider/settings_provider.dart';
import 'package:flixquest/video_providers/names.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Providers for a list of stored codes, so a test can save back the
/// order it loaded: scrapers by id, direct providers by their singletons.
List<VideoProvider> _providersFor(List<String> codes) => codes.map((code) {
      switch (code) {
        case 'direct:castle':
          return VideoProvider.directCastle;
        case 'direct:netmirror':
          return VideoProvider.directNetMirror;
        case 'direct:mxplayer':
          return VideoProvider.directMxPlayer;
        case 'direct:vixsrc':
          return VideoProvider.directVixSrc;
        default:
          return VideoProvider.scraper(
            id: code.replaceFirst('scraper:', ''),
            name: code,
          );
      }
    }).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sharedPrefsSingleton = await SharedPreferences.getInstance();
  });

  group('explicit custom provider order flag', () {
    test('a fresh install has no custom order', () async {
      final settings = SettingsProvider();
      await settings.getStreamProviderOrder();
      expect(settings.hasCustomStreamProviderOrder, isFalse);
    });

    test('a migrated legacy order is a base order, not a custom one',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'providerPrecedence-v14': 'movy-Zeila aethoflix-Karamara',
      });
      sharedPrefsSingleton = await SharedPreferences.getInstance();
      final prefs = SettingsPreferences();
      final order = await prefs.getStreamProviderOrder();
      expect(order, ['scraper:movy', 'scraper:aethoflix']);
      // The migrated list is stored, but the custom flag stays unset:
      // migration is not a choice, so category ordering still applies.
      expect(prefs.hasCustomStreamProviderOrder(), isFalse);
      final settings = SettingsProvider();
      await settings.getStreamProviderOrder();
      expect(settings.hasCustomStreamProviderOrder, isFalse);
    });

    test('a list stored before the flag existed still allows category order',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'stream_provider_order_v1': ['scraper:movy', 'scraper:aethoflix'],
      });
      sharedPrefsSingleton = await SharedPreferences.getInstance();
      final settings = SettingsProvider();
      await settings.getStreamProviderOrder();
      expect(settings.hasCustomStreamProviderOrder, isFalse);
    });

    test('a dialog save marks the order custom and persists it', () async {
      final settings = SettingsProvider();
      await settings.getStreamProviderOrder();
      settings.setStreamProviderOrder([
        VideoProvider.scraper(id: 'beta', name: 'Beta'),
        VideoProvider.directVixSrc,
      ]);
      expect(settings.hasCustomStreamProviderOrder, isTrue);
      final reloaded = SettingsProvider();
      await reloaded.getStreamProviderOrder();
      expect(reloaded.hasCustomStreamProviderOrder, isTrue);
      expect(
        reloaded.orderStreamProviders([
          VideoProvider.scraper(id: 'beta', name: 'Beta'),
          VideoProvider.directVixSrc,
        ]).map((provider) => provider.codeName),
        ['scraper:beta', 'direct:vixsrc'],
      );
    });

    test('a dialog save of the unchanged order still counts as custom',
        () async {
      final settings = SettingsProvider();
      await settings.getStreamProviderOrder();
      expect(settings.hasCustomStreamProviderOrder, isFalse);
      // Saving back exactly the loaded order: no reorder happened, but
      // the dialog save itself is the user owning the order.
      settings.setStreamProviderOrder(
        _providersFor(VideoProvider.defaultOrder),
      );
      expect(settings.hasCustomStreamProviderOrder, isTrue);
      final reloaded = SettingsProvider();
      await reloaded.getStreamProviderOrder();
      expect(reloaded.hasCustomStreamProviderOrder, isTrue);
    });
  });
}
