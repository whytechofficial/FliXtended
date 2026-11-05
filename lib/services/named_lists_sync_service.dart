import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/media_item.dart';
import '../controllers/named_lists_controller.dart';
import '../models/named_list.dart';

enum NamedListsSyncStatus { idle, syncing, success, error }

/// Named lists in Firestore, mirroring BookmarkSyncService: one document
/// per account, in its own collection, so a lists sync never touches the
/// bookmark document and a bookmark sync never touches this one.
///
/// The merge is a union, cloud first: lists union by id, titles union by
/// kind and TMDB id. A list's name and description are the one exception
/// to cloud-first — they follow the later `updated_at`, so an edit on
/// either device wins over the older text instead of being overwritten
/// by it.
///
/// Deletes cannot ride a union — a device holding a deleted list would
/// put it straight back — so removals go through explicit cloud calls,
/// exactly as bookmarks do. A device that was offline while a list was
/// deleted elsewhere still resurrects it on its next sync; that is the
/// same tradeoff bookmarks accept, and tombstones are the fix if it ever
/// bites.
class NamedListsSyncService {
  NamedListsSyncService._internal();
  static final NamedListsSyncService instance =
      NamedListsSyncService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NamedListsStore _store = SqfliteNamedListsStore();

  final ValueNotifier<NamedListsSyncStatus> statusNotifier =
      ValueNotifier<NamedListsSyncStatus>(NamedListsSyncStatus.idle);
  final ValueNotifier<DateTime?> lastSyncedNotifier =
      ValueNotifier<DateTime?>(null);

  bool _isSyncing = false;
  static const String _collection = 'named-lists-v1';
  static const String _lastSyncedKey = 'flixquest_last_named_lists_sync';

  /// The least time between automatic syncs for one account.
  static const Duration _autoSyncInterval = Duration(minutes: 10);
  static const Duration _changeDebounceDelay = Duration(seconds: 3);

  Timer? _changeDebounce;
  String? _lastAutoSyncUid;
  DateTime? _lastAutoSyncAt;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_lastSyncedKey);
    if (millis != null) {
      lastSyncedNotifier.value = DateTime.fromMillisecondsSinceEpoch(millis);
    }

    _auth.authStateChanges().listen((user) {
      if (user != null && !user.isAnonymous) {
        autoSyncIfSignedIn();
      }
    });
  }

  User? get currentUser => _auth.currentUser;
  bool get canSync => currentUser != null && !currentUser!.isAnonymous;

  Future<bool> checkIfDocExists(String uid) async {
    try {
      final doc = await _firestore.collection(_collection).doc(uid).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Unions this device's lists into the cloud document and returns the
  /// merged lists. The document is read once and only written when the
  /// merge changed it, so a sync with nothing new costs a single read.
  Future<List<NamedList>> _mergeLocalIntoCloud(String uid) async {
    final docRef = _firestore.collection(_collection).doc(uid);
    final docSnapshot = await docRef.get();
    final docData = docSnapshot.data() ?? {};

    final cloudLists = _listsFromDoc(docData);
    final localLists = await _store.getLists();
    final merged = mergeLists(cloudLists, localLists);

    final changed = !docSnapshot.exists || !_sameLists(cloudLists, merged);
    if (changed) {
      await docRef.set(
        {'lists': merged.map((list) => list.toMap()).toList()},
        SetOptions(merge: true),
      );
    }
    return merged;
  }

  /// Unions [cloud] and [local] lists: by id, cloud first; a list both
  /// sides hold takes the later name and description and the union of
  /// its titles.
  static List<NamedList> mergeLists(
    List<NamedList> cloud,
    List<NamedList> local,
  ) {
    final merged = <NamedList>[];
    final localById = <String, NamedList>{
      for (final list in local) list.id: list,
    };
    for (final cloudList in cloud) {
      final localList = localById.remove(cloudList.id);
      if (localList == null) {
        merged.add(cloudList);
        continue;
      }
      final cloudNewer =
          cloudList.updatedAt.compareTo(localList.updatedAt) >= 0;
      final items = <NamedListItem>[...cloudList.items];
      for (final item in localList.items) {
        if (!items.any(
          (entry) => entry.kind == item.kind && entry.tmdbId == item.tmdbId,
        )) {
          items.add(item);
        }
      }
      merged.add(
        NamedList(
          id: cloudList.id,
          name: cloudNewer ? cloudList.name : localList.name,
          description:
              cloudNewer ? cloudList.description : localList.description,
          createdAt: cloudList.createdAt,
          updatedAt: cloudNewer ? cloudList.updatedAt : localList.updatedAt,
          items: items,
        ),
      );
    }
    merged.addAll(localById.values);
    return merged;
  }

  /// Whether [a] and [b] hold the same lists, by id, name, description,
  /// timestamp and titles, so a no-change sync skips its write.
  static bool _sameLists(List<NamedList> a, List<NamedList> b) {
    if (a.length != b.length) return false;
    final byId = <String, NamedList>{
      for (final list in b) list.id: list,
    };
    for (final list in a) {
      final other = byId[list.id];
      if (other == null ||
          other.name != list.name ||
          other.description != list.description ||
          other.updatedAt != list.updatedAt ||
          other.items.length != list.items.length) {
        return false;
      }
      for (final item in list.items) {
        if (!other.items.any(
          (entry) => entry.kind == item.kind && entry.tmdbId == item.tmdbId,
        )) {
          return false;
        }
      }
    }
    return true;
  }

  static List<NamedList> _listsFromDoc(Map<String, dynamic> docData) {
    final raw = docData['lists'];
    if (raw is! List) return const <NamedList>[];
    final lists = <NamedList>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        lists.add(NamedList.fromMap(Map<String, Object?>.from(entry)));
      } catch (_) {
        // A malformed list is skipped, never allowed to sink the sync.
      }
    }
    return lists;
  }

  /// Triggers a background 2-way sync if the user is signed in and not
  /// anonymous. Repeats for the same account within [_autoSyncInterval]
  /// are skipped; a list change pushes on its own.
  Future<void> autoSyncIfSignedIn() async {
    if (!canSync || _isSyncing) return;
    final uid = currentUser!.uid;
    final lastAt = _lastAutoSyncAt;
    if (_lastAutoSyncUid == uid &&
        lastAt != null &&
        DateTime.now().difference(lastAt) < _autoSyncInterval) {
      return;
    }
    if (await syncNow()) {
      _lastAutoSyncUid = uid;
      _lastAutoSyncAt = DateTime.now();
    }
  }

  /// Schedules a sync after local lists change, coalescing quick edits
  /// into one.
  Future<void> onListsChanged() async {
    if (!canSync) return;
    _changeDebounce?.cancel();
    _changeDebounce = Timer(_changeDebounceDelay, () => unawaited(syncNow()));
  }

  /// Performs a full 2-way merge sync between the local database and
  /// Firestore.
  Future<bool> syncNow({bool force = false}) async {
    if (!canSync) return false;
    if (_isSyncing && !force) return false;

    _isSyncing = true;
    statusNotifier.value = NamedListsSyncStatus.syncing;

    try {
      final uid = currentUser!.uid;
      final merged = await _mergeLocalIntoCloud(uid);

      // Bring the local copy to the merged state: whole new lists in
      // full, known lists to the merged name and description, missing
      // titles added.
      final localLists = await _store.getLists();
      final localById = <String, NamedList>{
        for (final list in localLists) list.id: list,
      };
      for (final list in merged) {
        final local = localById[list.id];
        if (local == null) {
          await _store.insertFullList(list);
          continue;
        }
        if (local.name != list.name ||
            local.description != list.description ||
            local.updatedAt != list.updatedAt) {
          await _store.updateListRow(
            list.id,
            list.name,
            list.updatedAt,
            list.description,
          );
        }
        for (final item in list.items) {
          if (!local.items.any(
            (entry) => entry.kind == item.kind && entry.tmdbId == item.tmdbId,
          )) {
            await _store.insertItem(list.id, item);
          }
        }
      }

      final now = DateTime.now();
      lastSyncedNotifier.value = now;
      statusNotifier.value = NamedListsSyncStatus.success;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSyncedKey, now.millisecondsSinceEpoch);

      return true;
    } catch (e, stack) {
      if (kDebugMode) {
        print('NamedListsSyncService Error: $e\n$stack');
      }
      statusNotifier.value = NamedListsSyncStatus.error;
      return false;
    } finally {
      _isSyncing = false;
      if (statusNotifier.value == NamedListsSyncStatus.syncing) {
        statusNotifier.value = NamedListsSyncStatus.idle;
      }
    }
  }

  /// Syncs only offline/local lists up to cloud.
  Future<bool> pushLocalToCloud() async {
    if (!canSync) return false;
    try {
      await _mergeLocalIntoCloud(currentUser!.uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Syncs cloud lists down to the local database.
  Future<bool> pullCloudToLocal() async {
    if (!canSync) return false;
    try {
      final uid = currentUser!.uid;
      final docRef = _firestore.collection(_collection).doc(uid);
      final docSnapshot = await docRef.get();
      final docData = docSnapshot.data() ?? {};

      final localLists = await _store.getLists();
      final localById = <String, NamedList>{
        for (final list in localLists) list.id: list,
      };
      for (final list in _listsFromDoc(docData)) {
        final local = localById[list.id];
        if (local == null) {
          await _store.insertFullList(list);
          continue;
        }
        if (local.name != list.name ||
            local.description != list.description ||
            local.updatedAt != list.updatedAt) {
          await _store.updateListRow(
            list.id,
            list.name,
            list.updatedAt,
            list.description,
          );
        }
        for (final item in list.items) {
          if (!local.items.any(
            (entry) => entry.kind == item.kind && entry.tmdbId == item.tmdbId,
          )) {
            await _store.insertItem(list.id, item);
          }
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes a list from the cloud document. Local removal already
  /// happened; without this, the next merge would put it straight back.
  Future<bool> deleteListFromCloud(String listId) async {
    if (!canSync) return false;
    try {
      final uid = currentUser!.uid;
      final docRef = _firestore.collection(_collection).doc(uid);
      final docSnapshot = await docRef.get();
      final docData = docSnapshot.data() ?? {};

      final lists =
          _listsFromDoc(docData).where((list) => list.id != listId).toList();
      await docRef.update({
        'lists': lists.map((list) => list.toMap()).toList(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes one title from one list in the cloud document.
  Future<bool> deleteItemFromCloud(
    String listId,
    MediaKind kind,
    int tmdbId,
  ) async {
    if (!canSync) return false;
    try {
      final uid = currentUser!.uid;
      final docRef = _firestore.collection(_collection).doc(uid);
      final docSnapshot = await docRef.get();
      final docData = docSnapshot.data() ?? {};

      final lists = _listsFromDoc(docData);
      var changed = false;
      for (var i = 0; i < lists.length; i++) {
        if (lists[i].id != listId) continue;
        final items = lists[i]
            .items
            .where(
              (entry) => !(entry.kind == kind && entry.tmdbId == tmdbId),
            )
            .toList();
        if (items.length != lists[i].items.length) {
          lists[i] = lists[i].copyWith(items: items);
          changed = true;
        }
      }
      if (changed) {
        await docRef.update({
          'lists': lists.map((list) => list.toMap()).toList(),
        });
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
