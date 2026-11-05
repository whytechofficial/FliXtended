import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import 'package:flixquest/catalog/media_item.dart';
import 'package:flixquest/controllers/named_lists_controller.dart';
import 'package:flixquest/models/named_list.dart';
import 'package:flixquest/mobile/screens/named_list_detail_screen.dart';
import 'package:flixquest/mobile/widgets/named_list_dialogs.dart';
import 'package:flixquest/mobile/widgets/poster_card.dart';
import 'package:flixquest/provider/app_dependency_provider.dart';
import 'package:flixquest/provider/named_lists_provider.dart';
import 'package:flixquest/provider/settings_provider.dart';

/// An in-memory stand-in for the database, mirroring named_lists_test.
class _FakeStore implements NamedListsStore {
  final _lists = <String, NamedList>{};
  var _nextId = 0;

  @override
  Future<List<NamedList>> getLists() async => _lists.values.toList();

  @override
  Future<NamedList> insertList(String name, {String description = ''}) async {
    final list = NamedList(
      id: 'list-${_nextId++}',
      name: name,
      description: description,
      createdAt: DateTime.now().toString(),
    );
    _lists[list.id] = list;
    return list;
  }

  @override
  Future<void> renameList(String id, String name) async {
    final list = _lists[id];
    if (list != null) _lists[id] = list.copyWith(name: name);
  }

  @override
  Future<void> updateListDetails(
    String id,
    String name,
    String description,
  ) async {
    final list = _lists[id];
    if (list != null) {
      _lists[id] = list.copyWith(name: name, description: description);
    }
  }

  @override
  Future<void> deleteList(String id) async {
    _lists.remove(id);
  }

  @override
  Future<void> insertItem(String listId, NamedListItem item) async {
    final list = _lists[listId];
    if (list == null) return;
    if (list.items.any(
      (entry) => entry.kind == item.kind && entry.tmdbId == item.tmdbId,
    )) {
      return;
    }
    _lists[listId] = list.copyWith(items: [...list.items, item]);
  }

  @override
  Future<void> deleteItem(String listId, MediaKind kind, int tmdbId) async {
    final list = _lists[listId];
    if (list == null) return;
    _lists[listId] = list.copyWith(
      items: list.items
          .where(
            (entry) => !(entry.kind == kind && entry.tmdbId == tmdbId),
          )
          .toList(),
    );
  }

  @override
  Future<void> insertFullList(NamedList list) async {
    _lists[list.id] = list;
  }

  @override
  Future<void> updateListRow(
    String id,
    String name,
    String updatedAt,
    String description,
  ) async {
    final list = _lists[id];
    if (list != null) {
      _lists[id] = list.copyWith(
        name: name,
        description: description,
        updatedAt: updatedAt,
      );
    }
  }
}

MediaItem _movie(int id) => MediaItem(
      kind: MediaKind.movie,
      id: id,
      title: 'Film $id',
      overview: '',
      posterPath: '/p$id.jpg',
      backdropPath: null,
      rating: 8.0,
      releaseDate: '2020-01-01',
    );

Widget _app({
  required NamedListsProvider lists,
  required Widget child,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AppDependencyProvider()),
        ChangeNotifierProvider<NamedListsProvider>.value(value: lists),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'TMDB_API_KEY=test-key\n'
          'FLIXQUEST_API_URL=https://example.com',
    );
  });

  testWidgets('the sheet ticks lists holding the title, and toggles them',
      (tester) async {
    final lists = NamedListsProvider(store: _FakeStore());
    await lists.fetchLists();
    final inList = await lists.createList('In list') as NamedList;
    await lists.createList('Not in list');
    await lists.addToList(inList.id, _movie(550));

    await tester.pumpWidget(
      _app(
        lists: lists,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddToListSheet(context, _movie(550)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('In list'), findsOneWidget);
    expect(find.text('Not in list'), findsOneWidget);
    expect(
      find.byIcon(PhosphorIcons.check(PhosphorIconsStyle.bold)),
      findsOneWidget,
    );

    await tester.tap(find.text('Not in list'));
    await tester.pumpAndSettle();
    expect(lists.listsContaining(_movie(550)), hasLength(2));
    expect(
      find.byIcon(PhosphorIcons.check(PhosphorIconsStyle.bold)),
      findsNWidgets(2),
    );

    await tester.tap(find.text('Not in list'));
    await tester.pumpAndSettle();
    expect(lists.listsContaining(_movie(550)), hasLength(1));
  });

  testWidgets('the detail screen removes a title with its button',
      (tester) async {
    final lists = NamedListsProvider(store: _FakeStore());
    await lists.fetchLists();
    final list = await lists.createList('Watchlist') as NamedList;
    await lists.addToList(list.id, _movie(550));

    await tester.pumpWidget(
      _app(
        lists: lists,
        child: NamedListDetailScreen(listId: list.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PosterCard), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(lists.listById(list.id)!.items, isEmpty);
    expect(find.text('list_is_empty'), findsOneWidget);
  });
}
