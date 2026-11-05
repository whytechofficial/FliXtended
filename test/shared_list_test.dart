import 'package:flixquest/catalog/media_item.dart';
import 'package:flixquest/models/named_list.dart';
import 'package:flixquest/services/media_link.dart';
import 'package:flixquest/services/shared_list_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shared list links', () {
    test('a flixtended list address parses to its list id', () {
      final target =
          MediaLink.parse('https://flixtended.pages.dev/list/1762212345678901');
      expect(target, isA<SharedListLink>());
      expect((target as SharedListLink).listId, '1762212345678901');
    });

    test('the share address uses the app domain, never flix.quest', () {
      final url = MediaLink.sharedListUrl('1762212345678901');
      expect(
        url.toString(),
        'https://flixtended.pages.dev/list/1762212345678901',
      );
    });

    test('other flixtended paths still parse as before', () {
      expect(MediaLink.parse('https://flixtended.pages.dev/m/550'),
          isA<TmdbMovieLink>());
      expect(MediaLink.parse('https://flixtended.pages.dev/list/'),
          isNull);
    });
  });

  group('shared list snapshots', () {
    NamedList sampleList() => NamedList(
          id: '1762212345678901',
          name: 'Rainy day films',
          createdAt: '2026-11-03 10:00:00.000',
          description: 'For grey afternoons',
          items: <NamedListItem>[
            NamedListItem(
              kind: MediaKind.movie,
              tmdbId: 550,
              title: 'Fight Club',
              dateAdded: '2026-11-03 10:00:00.000',
              posterPath: '/poster.jpg',
            ),
          ],
        );

    test('a snapshot round-trips through the list shape', () {
      final map = SharedListService.snapshotMap(
        ownerUid: 'uid-1',
        ownerName: 'Aadil',
        list: sampleList(),
      );
      expect(map['ownerUid'], 'uid-1');
      expect(map['ownerName'], 'Aadil');
      final parsed = NamedList.fromMap(map);
      expect(parsed.name, 'Rainy day films');
      expect(parsed.description, 'For grey afternoons');
      expect(parsed.items, hasLength(1));
      expect(parsed.items.single.tmdbId, 550);
      expect(parsed.items.single.title, 'Fight Club');
    });
  });

  group('saved copy names', () {
    test('a free name stays as it is', () {
      expect(
        SharedListService.copyNameFor(
          const <String>['Other list'],
          'Rainy day films',
        ),
        'Rainy day films',
      );
    });

    test('a taken name gains a copy suffix that counts up', () {
      expect(
        SharedListService.copyNameFor(
          const <String>['Rainy day films'],
          'Rainy day films',
        ),
        'Rainy day films (copy)',
      );
      expect(
        SharedListService.copyNameFor(
          const <String>['Rainy day films', 'Rainy day films (copy)'],
          'Rainy day films',
        ),
        'Rainy day films (copy 2)',
      );
    });
  });
}
