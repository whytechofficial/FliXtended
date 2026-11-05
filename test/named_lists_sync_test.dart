import 'package:flutter_test/flutter_test.dart';

import 'package:flixquest/catalog/media_item.dart';
import 'package:flixquest/models/named_list.dart';
import 'package:flixquest/services/named_lists_sync_service.dart';

NamedListItem _item(
  int tmdbId, {
  MediaKind kind = MediaKind.movie,
}) =>
    NamedListItem(
      kind: kind,
      tmdbId: tmdbId,
      title: 'Film $tmdbId',
      posterPath: null,
      backdropPath: null,
      overview: '',
      releaseDate: null,
      rating: null,
      dateAdded: '2026-11-02',
    );

NamedList _list(
  String id, {
  String name = 'List',
  String description = '',
  String updatedAt = '2026-11-02 10:00:00.000Z',
  List<NamedListItem> items = const <NamedListItem>[],
}) =>
    NamedList(
      id: id,
      name: name,
      description: description,
      createdAt: '2026-11-01 10:00:00.000Z',
      updatedAt: updatedAt,
      items: items,
    );

void main() {
  group('mergeLists', () {
    test('cloud-only and local-only lists both survive', () {
      final merged = NamedListsSyncService.mergeLists(
        [_list('cloud')],
        [_list('local')],
      );
      expect(merged.map((list) => list.id), ['cloud', 'local']);
    });

    test('an empty merge is empty', () {
      expect(NamedListsSyncService.mergeLists([], []), isEmpty);
    });

    test('a list on both sides unions its titles without duplicates', () {
      final merged = NamedListsSyncService.mergeLists(
        [
          _list('a', items: [_item(550), _item(551)])
        ],
        [
          _list('a', items: [_item(551), _item(552)])
        ],
      );
      expect(merged, hasLength(1));
      expect(
        merged.first.items.map((item) => item.tmdbId),
        [550, 551, 552],
      );
    });

    test('the newer name wins, whichever side holds it', () {
      final cloudNewer = NamedListsSyncService.mergeLists(
        [_list('a', name: 'Cloud name', updatedAt: '2026-11-02 12:00:00.000Z')],
        [_list('a', name: 'Local name', updatedAt: '2026-11-02 10:00:00.000Z')],
      );
      expect(cloudNewer.first.name, 'Cloud name');
      expect(cloudNewer.first.updatedAt, '2026-11-02 12:00:00.000Z');

      final localNewer = NamedListsSyncService.mergeLists(
        [_list('a', name: 'Cloud name', updatedAt: '2026-11-02 10:00:00.000Z')],
        [_list('a', name: 'Local name', updatedAt: '2026-11-02 12:00:00.000Z')],
      );
      expect(localNewer.first.name, 'Local name');
      expect(localNewer.first.updatedAt, '2026-11-02 12:00:00.000Z');
    });

    test('a tie keeps the cloud name', () {
      final merged = NamedListsSyncService.mergeLists(
        [_list('a', name: 'Cloud name')],
        [_list('a', name: 'Local name')],
      );
      expect(merged.first.name, 'Cloud name');
    });

    test('the newer description wins, whichever side holds it', () {
      final cloudNewer = NamedListsSyncService.mergeLists(
        [
          _list('a',
              description: 'Cloud note', updatedAt: '2026-11-02 12:00:00.000Z'),
        ],
        [
          _list('a',
              description: 'Local note', updatedAt: '2026-11-02 10:00:00.000Z'),
        ],
      );
      expect(cloudNewer.first.description, 'Cloud note');

      final localNewer = NamedListsSyncService.mergeLists(
        [
          _list('a',
              description: 'Cloud note', updatedAt: '2026-11-02 10:00:00.000Z'),
        ],
        [
          _list('a',
              description: 'Local note', updatedAt: '2026-11-02 12:00:00.000Z'),
        ],
      );
      expect(localNewer.first.description, 'Local note');
    });

    test('series and movie titles with the same id are distinct', () {
      final merged = NamedListsSyncService.mergeLists(
        [
          _list('a', items: [_item(550, kind: MediaKind.movie)])
        ],
        [
          _list('a', items: [_item(550, kind: MediaKind.series)])
        ],
      );
      expect(merged.first.items, hasLength(2));
    });
  });

  group('document shape', () {
    test('a list round-trips through its map, items included', () {
      final list = _list('a', description: 'Rainy day', items: [_item(550)]);
      final restored = NamedList.fromMap(list.toMap());
      expect(restored.id, 'a');
      expect(restored.name, 'List');
      expect(restored.description, 'Rainy day');
      expect(restored.updatedAt, '2026-11-02 10:00:00.000Z');
      expect(restored.items.map((item) => item.tmdbId), [550]);
    });

    test('a map without a description reads as empty', () {
      final restored = NamedList.fromMap(<String, Object?>{
        'id': 'a',
        'name': 'List',
        'created_at': '2026-11-01 10:00:00.000Z',
        'updated_at': '2026-11-02 10:00:00.000Z',
      });
      expect(restored.description, isEmpty);
    });

    test('a map without updated_at falls back to created_at', () {
      final restored = NamedList.fromMap(<String, Object?>{
        'id': 'a',
        'name': 'List',
        'created_at': '2026-11-01 10:00:00.000Z',
        'items': <Map<String, Object?>>[],
      });
      expect(restored.updatedAt, '2026-11-01 10:00:00.000Z');
    });
  });
}
