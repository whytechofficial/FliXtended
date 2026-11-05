import 'package:flixquest/video_providers/category_order.dart';
import 'package:flixquest/video_providers/names.dart';
import 'package:flutter_test/flutter_test.dart';

VideoProvider _scraper(String id, String name) =>
    VideoProvider.scraper(id: id, name: name);

List<String> _codes(List<VideoProvider> providers) =>
    providers.map((provider) => provider.codeName).toList();

/// The catalog order the loaders hand in: direct providers first, then
/// the backend's scrapers.
final _catalog = <VideoProvider>[
  VideoProvider.directCastle,
  VideoProvider.directMxPlayer,
  VideoProvider.directNetMirror,
  VideoProvider.directVixSrc,
  _scraper('movy', 'Zeila'),
  _scraper('aethoflix', 'Karamara'),
  _scraper('animekai', 'Lalibela'),
  _scraper('animeyy', 'Magdala'),
  _scraper('animepahe', 'Maychew'),
  _scraper('metemma', 'Metemma'),
  _scraper('yoturkish', 'Sebastopol'),
];

void main() {
  group('categoryForTitle', () {
    test('India by name or code is Indian', () {
      expect(
        categoryForTitle(
          countries: ['India'],
          genres: ['Drama'],
          languages: ['Hindi'],
        ),
        TitleCategory.indian,
      );
      expect(
        categoryForTitle(
          countries: ['IN'],
          genres: ['Drama'],
          languages: [],
        ),
        TitleCategory.indian,
      );
    });

    test('animation needs a Japanese origin or language to be anime', () {
      expect(
        categoryForTitle(
          countries: ['Japan'],
          genres: ['Animation'],
          languages: ['Japanese'],
        ),
        TitleCategory.anime,
      );
      expect(
        categoryForTitle(
          countries: ['United States'],
          genres: ['Animation'],
          languages: ['English'],
        ),
        TitleCategory.general,
      );
      expect(
        categoryForTitle(
          countries: ['Japan'],
          genres: ['Drama'],
          languages: ['Japanese'],
        ),
        TitleCategory.general,
      );
    });

    test('Turkey by name or code is Turkish', () {
      expect(
        categoryForTitle(
          countries: ['Turkey'],
          genres: ['Drama'],
          languages: ['Turkish'],
        ),
        TitleCategory.turkish,
      );
    });

    test('no metadata at all stays general', () {
      expect(
        categoryForTitle(countries: [], genres: [], languages: []),
        TitleCategory.general,
      );
    });
  });

  group('applyCategoryOrder', () {
    test('an Indian title tries Karamara, Hampi, Nalanda, Dholavira first', () {
      final ordered = applyCategoryOrder(
        _catalog,
        countries: ['India'],
        genres: ['Drama'],
        languages: ['Hindi'],
      );
      expect(
        _codes(ordered).take(4),
        [
          'scraper:aethoflix',
          'direct:castle',
          'direct:netmirror',
          'direct:mxplayer',
        ],
      );
      // Everything else follows in its existing relative order.
      expect(
        _codes(ordered).skip(4),
        [
          'direct:vixsrc',
          'scraper:movy',
          'scraper:animekai',
          'scraper:animeyy',
          'scraper:animepahe',
          'scraper:metemma',
          'scraper:yoturkish',
        ],
      );
    });

    test('an anime title tries its four sources first, Metemma by name', () {
      final ordered = applyCategoryOrder(
        _catalog,
        countries: ['Japan'],
        genres: ['Animation'],
        languages: ['Japanese'],
      );
      expect(
        _codes(ordered).take(4),
        [
          'scraper:animekai',
          'scraper:animeyy',
          'scraper:animepahe',
          'scraper:metemma',
        ],
      );
      expect(_codes(ordered).skip(4).first, 'direct:castle');
    });

    test('a Turkish title tries Sebastopol first', () {
      final ordered = applyCategoryOrder(
        _catalog,
        countries: ['Turkey'],
        genres: ['Drama'],
        languages: ['Turkish'],
      );
      expect(_codes(ordered).first, 'scraper:yoturkish');
      expect(_codes(ordered).skip(1).first, 'direct:castle');
    });

    test('a general title keeps its order untouched', () {
      final ordered = applyCategoryOrder(
        _catalog,
        countries: ['United States'],
        genres: ['Drama'],
        languages: ['English'],
      );
      expect(_codes(ordered), _codes(_catalog));
    });

    test('empty metadata keeps the order untouched', () {
      final ordered = applyCategoryOrder(
        _catalog,
        countries: [],
        genres: [],
        languages: [],
      );
      expect(_codes(ordered), _codes(_catalog));
    });

    test('from the default order, an Indian title pulls Karamara first',
        () {
      // The order a loader hands in when no custom order exists: Zeila,
      // Abyssinia, Gura first — the exact sequence a default-order user
      // saw before the flag fix, instead of Karamara first.
      final defaultOrdered = <VideoProvider>[
        _scraper('movy', 'Zeila'),
        _scraper('cinejoy', 'Abyssinia'),
        _scraper('vidup', 'Gura'),
        _scraper('aethoflix', 'Karamara'),
        VideoProvider.directCastle,
        VideoProvider.directNetMirror,
        VideoProvider.directMxPlayer,
        VideoProvider.directVixSrc,
      ];
      final ordered = applyCategoryOrder(
        defaultOrdered,
        countries: ['India'],
        genres: ['Drama'],
        languages: ['Hindi'],
      );
      expect(
        _codes(ordered).take(4),
        [
          'scraper:aethoflix',
          'direct:castle',
          'direct:netmirror',
          'direct:mxplayer',
        ],
      );
      expect(
        _codes(ordered).skip(4).take(3),
        ['scraper:movy', 'scraper:cinejoy', 'scraper:vidup'],
      );
    });

    test('missing priority providers are simply absent, not errors', () {
      final ordered = applyCategoryOrder(
        [VideoProvider.directVixSrc, _scraper('movy', 'Zeila')],
        countries: ['India'],
        genres: ['Drama'],
        languages: ['Hindi'],
      );
      expect(
        _codes(ordered),
        ['direct:vixsrc', 'scraper:movy'],
      );
    });
  });
}
