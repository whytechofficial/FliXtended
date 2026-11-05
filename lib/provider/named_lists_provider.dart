import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../catalog/media_item.dart';
import '../controllers/named_lists_controller.dart';
import '../models/named_list.dart';
import '../services/named_lists_sync_service.dart';
import '../services/shared_list_service.dart';
import '../services/imdb_list_import.dart';
import '../services/tmdb_list_import.dart';

/// The user's named lists, local for now. Mirrors BookmarkProvider: the
/// provider owns the in-memory copy and every change goes through the
/// store first, then reloads, so the screen never shows a write that did
/// not land. Sync arrives in Phase 2, in its own service and its own
/// collection, and touches nothing here except through these methods.
class NamedListsProvider extends ChangeNotifier {
  NamedListsProvider({NamedListsStore? store})
      : _store = store ?? SqfliteNamedListsStore() {
    // Guarded: sync service requires Firebase; skip if unavailable.
    try {
      NamedListsSyncService.instance.statusNotifier
          .addListener(_onSyncStatusChanged);
    } catch (_) {}
  }

  final NamedListsStore _store;

  List<NamedList> _lists = [];
  List<NamedList> get lists => _lists;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void _onSyncStatusChanged() {
    try {
      final status = NamedListsSyncService.instance.statusNotifier.value;
      if (status == NamedListsSyncStatus.success) {
        fetchLists();
      }
    } catch (_) {}
  }

  /// A sync push is best-effort: Firebase missing must never break a
  /// local write, so a failing push is swallowed here and retried by
  /// the next change or auto-sync.
  void _notifySync() {
    try {
      NamedListsSyncService.instance.onListsChanged();
    } catch (_) {}
  }

  /// Republishes a shared list after a local change, so the public
  /// snapshot never goes stale behind the link. Best-effort like a
  /// sync push: a failed refresh must never break the local write.
  void _refreshShared(String listId) {
    try {
      final list = listById(listId);
      if (list == null) return;
      unawaited(SharedListService.instance.refreshIfPublic(list));
    } catch (_) {}
  }

  Future<void> fetchLists() async {
    _isLoading = true;
    notifyListeners();
    try {
      _lists = await _store.getLists();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates a list and returns it, or null for a blank name.
  Future<NamedList?> createList(String name, {String description = ''}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final list = await _store.insertList(
      trimmed,
      description: description.trim(),
    );
    await fetchLists();
    _notifySync();
    return list;
  }

  Future<void> renameList(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _store.renameList(id, trimmed);
    await fetchLists();
    _notifySync();
  }

  /// Saves a list's name and description together, as the edit dialog
  /// does. A blank name saves nothing, as a rename alone would not.
  Future<void> updateListDetails(
    String id,
    String name,
    String description,
  ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _store.updateListDetails(id, trimmed, description.trim());
    await fetchLists();
    _notifySync();
    _refreshShared(id);
  }

  Future<void> deleteList(String id) async {
    await _store.deleteList(id);
    await fetchLists();
    try {
      await NamedListsSyncService.instance.deleteListFromCloud(id);
    } catch (_) {}
    try {
      await SharedListService.instance.unpublish(id);
    } catch (_) {}
    _notifySync();
  }

  /// Adds [item] to the list, or does nothing when it is already there.
  Future<void> addToList(String listId, MediaItem item) async {
    if (item.id < 0) return;
    await _store.insertItem(listId, NamedListItem.fromMediaItem(item));
    await fetchLists();
    _notifySync();
    _refreshShared(listId);
  }

  Future<void> removeFromList(
    String listId,
    MediaKind kind,
    int tmdbId,
  ) async {
    await _store.deleteItem(listId, kind, tmdbId);
    await fetchLists();
    try {
      await NamedListsSyncService.instance
          .deleteItemFromCloud(listId, kind, tmdbId);
    } catch (_) {}
    _notifySync();
    _refreshShared(listId);
  }

  /// Saves someone else's shared list as the viewer's own: the same
  /// name when it is free, otherwise the name with a " (copy)" suffix
  /// that counts up. Returns the created list, or null for a blank
  /// name. The copy syncs like any list the viewer made themselves.
  Future<NamedList?> saveSharedCopy(SharedListSnapshot shared) async {
    final name = SharedListService.copyNameFor(
      _lists.map((list) => list.name),
      shared.list.name,
    );
    if (name.trim().isEmpty) return null;
    final created = await _store.insertList(
      name,
      description: shared.list.description,
    );
    for (final item in shared.list.items) {
      await _store.insertItem(created.id, item);
    }
    await fetchLists();
    _notifySync();
    return created;
  }

  /// The lists [item] is already in, for the add-to-list sheet's ticks.
  List<NamedList> listsContaining(MediaItem item) => _lists
      .where(
        (list) => list.items.any(
          (entry) => entry.kind == item.kind && entry.tmdbId == item.id,
        ),
      )
      .toList(growable: false);

  NamedList? listById(String id) {
    for (final list in _lists) {
      if (list.id == id) return list;
    }
    return null;
  }

  /// Creates a list from a public TMDB list link. Throws
  /// [TmdbListImportException] for a link that is not a list, a failed
  /// fetch, or a list with no titles in it.
  Future<NamedList> importFromTmdb(
    String link, {
    String proxyUrl = '',
    Future<http.Response> Function(String url, String proxyUrl)? fetch,
  }) async {
    final listId = TmdbListImport.parseId(link);
    if (listId == null) {
      throw const TmdbListImportException(TmdbListImportError.invalidLink);
    }
    final result = await TmdbListImport.fetchList(
      listId,
      proxyUrl: proxyUrl,
      fetch: fetch,
    );
    final list = await _store.insertList(result.name);
    for (final item in result.items) {
      await _store.insertItem(list.id, item);
    }
    await fetchLists();
    _notifySync();
    return list;
  }

  /// Creates a list from a public IMDb list link. Titles that do not
  /// resolve to a TMDB id are skipped; the same
  /// [TmdbListImportException] errors report a bad link, a failed
  /// fetch, or a list with no resolvable titles in it. [fetchPageViaBrowser]
  /// loads a page in a real browser engine, used only when IMDb's bot
  /// wall turns the plain request away; the import screen supplies it.
  Future<NamedList> importFromImdb(
    String link, {
    String proxyUrl = '',
    Future<http.Response> Function(String url)? fetchPage,
    Future<String?> Function(String url)? fetchPageViaBrowser,
    Future<NamedListItem?> Function(String imdbId)? resolve,
  }) async {
    final listId = ImdbListImport.parseId(link);
    if (listId == null) {
      throw const TmdbListImportException(TmdbListImportError.invalidLink);
    }
    final result = await ImdbListImport.fetchList(
      listId,
      proxyUrl: proxyUrl,
      fetchPage: fetchPage,
      fetchPageViaBrowser: fetchPageViaBrowser,
      resolve: resolve,
    );
    final list = await _store.insertList(result.name);
    for (final item in result.items) {
      await _store.insertItem(list.id, item);
    }
    await fetchLists();
    _notifySync();
    return list;
  }

  /// Creates a list from a public TMDB or IMDb list link, routed by the
  /// link itself. Anything else throws the invalid-link error, so the
  /// import dialog needs only one entry point for both sources.
  Future<NamedList> importFromLink(
    String link, {
    String proxyUrl = '',
    Future<http.Response> Function(String url, String proxyUrl)? fetch,
    Future<http.Response> Function(String url)? fetchPage,
    Future<String?> Function(String url)? fetchPageViaBrowser,
    Future<NamedListItem?> Function(String imdbId)? resolve,
  }) async {
    if (TmdbListImport.parseId(link) != null) {
      return importFromTmdb(link, proxyUrl: proxyUrl, fetch: fetch);
    }
    if (ImdbListImport.parseId(link) != null) {
      return importFromImdb(
        link,
        proxyUrl: proxyUrl,
        fetchPage: fetchPage,
        fetchPageViaBrowser: fetchPageViaBrowser,
        resolve: resolve,
      );
    }
    throw const TmdbListImportException(TmdbListImportError.invalidLink);
  }

  @override
  void dispose() {
    try {
      NamedListsSyncService.instance.statusNotifier
          .removeListener(_onSyncStatusChanged);
    } catch (_) {}
    super.dispose();
  }
}
