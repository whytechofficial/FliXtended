import 'package:flixquest/catalog/catalog_controller.dart';
import 'package:flixquest/catalog/media_item.dart';
import 'package:flixquest/catalog/regional_language.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared contract behind the regional Top 10 rows: TV Home and the
/// TV Movies/Series pages read the same languages, in the same order,
/// from the same discover queries. The controller fetch itself hits the
/// network, so on-device proof is still needed for the rows appearing;
/// these tests pin what the fetch and the row builders agree on.
void main() {
  test('regional languages keep Home\'s order', () {
    expect(
      RegionalLanguage.values.map((language) => language.code).toList(),
      ['ml', 'ta', 'hi', 'te'],
    );
    expect(
      RegionalLanguage.values.map((language) => language.name).toList(),
      ['Malayalam', 'Tamil', 'Hindi', 'Telugu'],
    );
  });

  test('catalog data defaults to no regional rows', () {
    const data = CatalogData(
      kind: MediaKind.movie,
      topTen: [],
      trending: [],
      popular: [],
      topRated: [],
      fresh: [],
      serviceShelves: [],
      genres: [],
    );
    expect(data.regional, isEmpty);
  });
}
