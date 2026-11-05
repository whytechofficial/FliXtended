import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/named_list.dart';

/// A named list published for anyone with its link, and the service that
/// publishes it.
///
/// WHY A SEPARATE COLLECTION: named lists live as one document per
/// account (`named-lists-v1/{uid}`) holding a `lists` array, and
/// Firestore rules grant access per document, never per array entry —
/// so a "public" flag inside that document could not make one list
/// public without exposing every list in it. A public list is therefore
/// a snapshot of its own in `shared-lists-v1/{listId}`: readable by
/// anyone, writable only by its owner, deleted the moment sharing turns
/// off or the list itself is deleted. Private lists never leave the
/// per-account document.
///
/// The public flag itself lives on this device (SharedPreferences) and
/// in the snapshot's existence: toggling on writes the snapshot,
/// toggling off deletes it. A second device learns the truth from the
/// cloud copy instead (see [isSharedOnCloud]), so a toggle made on one
/// device is not contradicted by stale state on another.
class SharedListService {
  SharedListService._internal();
  static final SharedListService instance = SharedListService._internal();

  static const String collection = 'shared-lists-v1';
  static const String _publicIdsKey = 'shared_list_ids';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// The public snapshot for [list]: the owner's id and name plus the
  /// list itself, in exactly the shape [NamedList.fromMap] reads, so a
  /// recipient renders the same rows the owner sees.
  static Map<String, Object?> snapshotMap({
    required String ownerUid,
    required String ownerName,
    required NamedList list,
  }) {
    final map = list.toMap();
    map['ownerUid'] = ownerUid;
    map['ownerName'] = ownerName;
    return map;
  }

  /// The name a saved copy takes: the original name when the viewer
  /// has no list by it, otherwise the original with a " (copy)" suffix
  /// that counts up until it is free.
  static String copyNameFor(Iterable<String> existingNames, String name) {
    final taken = existingNames.map((entry) => entry.trim()).toSet();
    if (!taken.contains(name)) return name;
    if (!taken.contains('$name (copy)')) return '$name (copy)';
    var copy = 2;
    while (taken.contains('$name (copy $copy)')) {
      copy++;
    }
    return '$name (copy $copy)';
  }

  Future<Set<String>> _publicIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_publicIdsKey);
    if (raw == null) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _setPublicIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_publicIdsKey, jsonEncode(ids.toList()));
  }

  /// Whether this device has sharing on for [listId].
  Future<bool> isPublic(String listId) async =>
      (await _publicIds()).contains(listId);

  /// The owner's display name for a snapshot: the users record first,
  /// then the Firebase display name, then the email's local part.
  Future<String> ownerNameFor(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final name = doc.data()?['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    final user = _auth.currentUser;
    final display = user?.displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final email = user?.email ?? '';
    final local = email.split('@').first.trim();
    if (local.isNotEmpty) return local;
    return 'FliXtended user';
  }

  /// Publishes [list] for anyone with its link. Returns false when
  /// there is no signed-in, non-anonymous owner to attribute it to;
  /// anything else throws, so the sheet can say the publish failed
  /// (for example before the sharing rules are published).
  Future<bool> publish(NamedList list) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return false;
    final ownerName = await ownerNameFor(user.uid);
    await _firestore.collection(collection).doc(list.id).set(
          snapshotMap(ownerUid: user.uid, ownerName: ownerName, list: list),
        );
    final ids = await _publicIds()..add(list.id);
    await _setPublicIds(ids);
    return true;
  }

  /// Removes the public snapshot, so the link stops working. The local
  /// flag clears only once the cloud delete lands — a failed delete
  /// returns false and leaves sharing on, so a retry can still work.
  Future<bool> unpublish(String listId) async {
    try {
      await _firestore.collection(collection).doc(listId).delete();
    } catch (_) {
      return false;
    }
    final ids = await _publicIds()..remove(listId);
    await _setPublicIds(ids);
    return true;
  }

  /// Republishes [list] when this device has sharing on for it, so a
  /// rename, a description edit or a title added or removed reaches
  /// the link. A no-op for private lists and for signed-out devices,
  /// and never allowed to break the local write that triggered it.
  Future<void> refreshIfPublic(NamedList list) async {
    if (!await isPublic(list.id)) return;
    try {
      await publish(list);
    } catch (_) {}
  }

  /// Whether the cloud copy exists and belongs to [uid]: the truth a
  /// second device checks when its own toggle state is unknown.
  Future<bool> isSharedOnCloud(String listId, String uid) async {
    try {
      final doc = await _firestore.collection(collection).doc(listId).get();
      final data = doc.data();
      return doc.exists && data != null && data['ownerUid'] == uid;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the public snapshot for [listId], or null when there is
  /// none, the link went private, or the read is refused (for example
  /// before the sharing rules are published).
  Future<SharedListSnapshot?> fetchShared(String listId) async {
    try {
      final doc = await _firestore.collection(collection).doc(listId).get();
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      final ownerUid = data['ownerUid'];
      final ownerName = data['ownerName'];
      if (ownerUid is! String || ownerName is! String) return null;
      final map = Map<String, Object?>.from(data)..['id'] = listId;
      return SharedListSnapshot(
        ownerUid: ownerUid,
        ownerName: ownerName,
        list: NamedList.fromMap(map),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A public list as a recipient sees it: who shared it, and the list.
class SharedListSnapshot {
  const SharedListSnapshot({
    required this.ownerUid,
    required this.ownerName,
    required this.list,
  });

  final String ownerUid;
  final String ownerName;
  final NamedList list;
}
