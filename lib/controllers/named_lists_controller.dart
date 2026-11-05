import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../catalog/media_item.dart';
import '../models/named_list.dart';

/// Where named lists live. The provider talks to this interface, never to
/// the database directly, so tests can stand in with a fake and the sync
/// step later can reuse the same shape.
abstract class NamedListsStore {
  Future<List<NamedList>> getLists();
  Future<NamedList> insertList(String name, {String description = ''});
  Future<void> renameList(String id, String name);

  /// Sets a list's name and description together, stamping the write
  /// time, as the edit dialog does. A rename alone still goes through
  /// [renameList]; this is the one write that carries a description.
  Future<void> updateListDetails(
    String id,
    String name,
    String description,
  );
  Future<void> deleteList(String id);
  Future<void> insertItem(String listId, NamedListItem item);
  Future<void> deleteItem(String listId, MediaKind kind, int tmdbId);

  /// Writes [list] whole, with its own id and timestamps, as sync-down
  /// does for a list this device has never seen. Replaces the row when
  /// one with the id is already there.
  Future<void> insertFullList(NamedList list);

  /// Sets a list's name, description and timestamp exactly, as sync-down
  /// does for the merged list. Unlike [renameList], this never stamps
  /// the write time.
  Future<void> updateListRow(
    String id,
    String name,
    String updatedAt,
    String description,
  );
}

/// Named lists on disk, in their own database file so no migration ever
/// touches the bookmark tables.
class SqfliteNamedListsStore implements NamedListsStore {
  static SqfliteNamedListsStore? _instance;
  static Database? _database;

  SqfliteNamedListsStore._createInstance();

  factory SqfliteNamedListsStore() {
    _instance ??= SqfliteNamedListsStore._createInstance();
    return _instance!;
  }

  Future<Database> get database async {
    _database ??= await _open();
    return _database!;
  }

  Future<Database> _open() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    return openDatabase(
      '${directory.path}named_lists.db',
      version: 2,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE named_lists('
          'id TEXT PRIMARY KEY, '
          'name TEXT NOT NULL, '
          'description TEXT NOT NULL DEFAULT \'\', '
          'created_at TEXT NOT NULL, '
          'updated_at TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE named_list_items('
          'list_id TEXT NOT NULL, '
          'kind TEXT NOT NULL, '
          'tmdb_id INTEGER NOT NULL, '
          'title TEXT NOT NULL, '
          'poster_path TEXT, '
          'backdrop_path TEXT, '
          'overview TEXT, '
          'release_date TEXT, '
          'vote_average REAL, '
          'date_added TEXT NOT NULL, '
          'PRIMARY KEY (list_id, kind, tmdb_id))',
        );
      },
      onUpgrade: (db, oldVersion, _) async {
        // Beta 41 lists carry no description column; the column arrives
        // empty and the model reads it as "no description".
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE named_lists '
            "ADD COLUMN description TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
  }

  @override
  Future<List<NamedList>> getLists() async {
    final db = await database;
    final listRows = await db.query('named_lists', orderBy: 'created_at ASC');
    final lists = <NamedList>[];
    for (final row in listRows) {
      final id = row['id'] as String;
      final itemRows = await db.query(
        'named_list_items',
        where: 'list_id = ?',
        whereArgs: [id],
        orderBy: 'date_added DESC',
      );
      lists.add(
        NamedList.fromMap(
          row,
          itemRows.map(NamedListItem.fromMap).toList(growable: false),
        ),
      );
    }
    return lists;
  }

  @override
  Future<NamedList> insertList(String name, {String description = ''}) async {
    final db = await database;
    final now = DateTime.now();
    final list = NamedList(
      id: '${now.microsecondsSinceEpoch}',
      name: name,
      description: description,
      createdAt: now.toString(),
      updatedAt: now.toUtc().toString(),
    );
    await db.insert(
      'named_lists',
      // The row holds the list alone; its items live in their own table.
      list.toMap()..remove('items'),
    );
    return list;
  }

  @override
  Future<void> renameList(String id, String name) async {
    final db = await database;
    // A rename is the one write a sync conflict looks at, so it stamps
    // the time; item writes never do (they union on merge regardless).
    await db.update(
      'named_lists',
      {'name': name, 'updated_at': DateTime.now().toUtc().toString()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> updateListDetails(
    String id,
    String name,
    String description,
  ) async {
    final db = await database;
    // A description edit rides the same timestamp a rename does, so a
    // sync conflict over it resolves the same way: later wins.
    await db.update(
      'named_lists',
      {
        'name': name,
        'description': description,
        'updated_at': DateTime.now().toUtc().toString(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> insertFullList(NamedList list) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'named_lists',
        list.toMap()..remove('items'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'named_list_items',
        where: 'list_id = ?',
        whereArgs: [list.id],
      );
      for (final item in list.items) {
        await txn.insert(
          'named_list_items',
          item.toMap(list.id),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> updateListRow(
    String id,
    String name,
    String updatedAt,
    String description,
  ) async {
    final db = await database;
    await db.update(
      'named_lists',
      {'name': name, 'updated_at': updatedAt, 'description': description},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteList(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'named_list_items',
        where: 'list_id = ?',
        whereArgs: [id],
      );
      await txn.delete('named_lists', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> insertItem(String listId, NamedListItem item) async {
    final db = await database;
    // Adding a title that is already in the list changes nothing.
    await db.insert(
      'named_list_items',
      item.toMap(listId),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> deleteItem(String listId, MediaKind kind, int tmdbId) async {
    final db = await database;
    await db.delete(
      'named_list_items',
      where: 'list_id = ? AND kind = ? AND tmdb_id = ?',
      whereArgs: [listId, kind.name, tmdbId],
    );
  }
}
