import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'shared_list_service.dart';
import 'wellness_sync_service.dart';

/// What an account change's failure means: a stable [code] the TV form
/// maps to its own words, plus the raw [message] as a fallback.
class TvAccountException implements Exception {
  const TvAccountException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'TvAccountException($code): $message';
}

/// What the TV account screens show and edit: the Firebase user's profile
/// as FliXtended stores it (the `users` document plus the Auth user).
class TvAccountProfile {
  const TvAccountProfile({
    required this.name,
    required this.username,
    required this.email,
    required this.profileId,
    required this.photoUrl,
    required this.isGoogleOnly,
  });

  final String name;
  final String username;
  final String email;
  final int profileId;
  final String photoUrl;

  /// True when Google is the only way this account signs in: there is no
  /// password to re-authenticate with, so sensitive changes re-authenticate
  /// through Google instead.
  final bool isGoogleOnly;
}

/// The account operations the TV manage-account screens need, against
/// FliXtended's Firebase stack (not upstream's Laravel backend).
abstract class TvAccountService {
  /// The signed-in profile, or null when nobody is signed in.
  Future<TvAccountProfile?> currentProfile();

  /// Whether [username] is free (or already this account's own).
  Future<bool> usernameAvailable(String username);

  /// Saves the profile: the `users` document (name, username, picture)
  /// plus the Auth display name. A changed username is reserved first and
  /// the old reservation released, in one batch.
  Future<void> updateProfile({
    required String name,
    required String username,
    required int profileId,
    required String photoUrl,
  });

  /// Changes the email, re-authenticating first (with the current password,
  /// or through Google for Google-only accounts). firebase_auth no longer
  /// offers a direct email change: the new address is verified first
  /// ([User.verifyBeforeUpdateEmail]), so the address itself only changes
  /// once the user clicks the link in the new inbox — the copy on the
  /// form and the snackbar says exactly that.
  Future<void> changeEmail({
    required String currentPassword,
    required String email,
  });

  /// Changes the password, re-authenticating first. Unlike upstream's
  /// server, Firebase does NOT sign out other devices on a password
  /// change without token revocation (which needs the Admin SDK, which
  /// FliXtended does not have) — so this deliberately signs nothing out
  /// anywhere; the TV simply keeps its own session.
  Future<void> changePassword({
    required String currentPassword,
    required String password,
  });

  /// The full wipe: every Firestore document this account owns, then the
  /// Firebase user itself. The cleanup must fully succeed before the user
  /// is deleted — a half-wipe (data gone, account alive, or account gone
  /// with orphaned data) is never left behind, so any cleanup failure
  /// aborts before [FirebaseAuth] delete is called.
  Future<void> deleteAccount();
}

/// [TvAccountService] on Firebase Auth + Firestore.
class FirebaseTvAccountService implements TvAccountService {
  FirebaseTvAccountService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
    WellnessSyncService? wellness,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _wellness = wellness ?? WellnessSyncService();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;
  final WellnessSyncService _wellness;

  /// Firebase treats a sign-in as recent for only a few minutes. A delete
  /// has no password to re-authenticate with, so a stale session is
  /// refused up front — before any data is touched — instead of wiping
  /// first and failing the delete after.
  static const _recentLoginWindow = Duration(minutes: 5);

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw const TvAccountException(
        code: 'not-signed-in',
        message: 'Nobody is signed in.',
      );
    }
    return user;
  }

  Future<Map<String, dynamic>?> _userDoc(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    return snapshot.data();
  }

  bool _isGoogleOnly(User user, Map<String, dynamic>? doc) {
    final providers =
        user.providerData.map((info) => info.providerId).toSet();
    if (providers.isNotEmpty) {
      return providers.every((provider) => provider == 'google.com');
    }
    return doc?['provider']?.toString() == 'google';
  }

  @override
  Future<TvAccountProfile?> currentProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _userDoc(user.uid);
    final profileId = doc?['profileId'];
    return TvAccountProfile(
      name: doc?['name']?.toString().trim().isNotEmpty == true
          ? doc!['name'].toString().trim()
          : (user.displayName ?? ''),
      username: doc?['username']?.toString() ?? '',
      email: user.email ?? doc?['email']?.toString() ?? '',
      profileId: profileId is int
          ? profileId
          : int.tryParse(profileId?.toString() ?? '') ?? 0,
      photoUrl: doc?['photoUrl']?.toString() ?? user.photoURL ?? '',
      isGoogleOnly: _isGoogleOnly(user, doc),
    );
  }

  @override
  Future<bool> usernameAvailable(String username) async {
    final normalized = username.toLowerCase().trim();
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await _userDoc(user.uid);
      if (doc?['username']?.toString() == normalized) return true;
    }
    final reservation = await _firestore
        .collection('usernames')
        .doc(normalized)
        .get();
    return !reservation.exists;
  }

  @override
  Future<void> updateProfile({
    required String name,
    required String username,
    required int profileId,
    required String photoUrl,
  }) async {
    final user = _user;
    final normalized = username.toLowerCase().trim();
    final doc = await _userDoc(user.uid);
    final previous = doc?['username']?.toString() ?? '';
    if (normalized != previous && !await usernameAvailable(normalized)) {
      throw const TvAccountException(
        code: 'username-already-in-use',
        message: 'That username is already in use.',
      );
    }
    final batch = _firestore.batch();
    if (normalized != previous) {
      batch.set(
        _firestore.collection('usernames').doc(normalized),
        <String, Object>{'uname': normalized, 'uid': user.uid},
      );
      if (previous.isNotEmpty) {
        batch.delete(_firestore.collection('usernames').doc(previous));
      }
    }
    batch.update(_firestore.collection('users').doc(user.uid), <String, Object>{
      'name': name,
      'username': normalized,
      'profileId': profileId,
      'photoUrl': photoUrl,
    });
    await batch.commit();
    try {
      await user.updateDisplayName(name);
    } catch (_) {
      // The document is the profile the app shows; a display-name miss
      // must not fail a save that already landed.
    }
  }

  Future<void> _reauthenticate({
    required User user,
    required bool isGoogleOnly,
    required String currentPassword,
  }) async {
    try {
      if (isGoogleOnly) {
        final googleAccount = await _googleSignIn.signIn();
        if (googleAccount == null) {
          throw const TvAccountException(
            code: 'cancelled',
            message: 'Sign-in cancelled.',
          );
        }
        final googleAuth = await googleAccount.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
      } else {
        final credential = EmailAuthProvider.credential(
          email: user.email ?? '',
          password: currentPassword,
        );
        await user.reauthenticateWithCredential(credential);
      }
    } on TvAccountException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw TvAccountException(
        code: _reauthCode(error),
        message: error.message ?? 'Could not confirm it is you.',
      );
    }
  }

  String _reauthCode(FirebaseAuthException error) => switch (error.code) {
        'wrong-password' || 'invalid-credential' => 'wrong-password',
        'network-request-failed' => 'network-request-failed',
        _ => error.code,
      };

  @override
  Future<void> changeEmail({
    required String currentPassword,
    required String email,
  }) async {
    final user = _user;
    final profile = await currentProfile();
    final normalized = email.toLowerCase().trim();
    await _reauthenticate(
      user: user,
      isGoogleOnly: profile?.isGoogleOnly ?? false,
      currentPassword: currentPassword,
    );
    try {
      // No users-document write here: the address has not changed yet and
      // only changes once the new inbox is verified.
      await user.verifyBeforeUpdateEmail(normalized);
    } on FirebaseAuthException catch (error) {
      throw TvAccountException(
        code: error.code,
        message: error.message ?? 'Could not change the email.',
      );
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String password,
  }) async {
    final user = _user;
    final profile = await currentProfile();
    await _reauthenticate(
      user: user,
      isGoogleOnly: profile?.isGoogleOnly ?? false,
      currentPassword: currentPassword,
    );
    try {
      await user.updatePassword(password);
    } on FirebaseAuthException catch (error) {
      throw TvAccountException(
        code: _reauthCode(error),
        message: error.message ?? 'Could not change the password.',
      );
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _user;
    final uid = user.uid;
    final lastSignIn = user.metadata.lastSignInTime;
    if (lastSignIn == null ||
        DateTime.now().difference(lastSignIn) > _recentLoginWindow) {
      throw const TvAccountException(
        code: 'requires-recent-login',
        message: 'Sign in again before deleting.',
      );
    }
    final doc = await _userDoc(uid);
    final username = doc?['username']?.toString() ?? '';
    final snapshots = await _firestore
        .collection(SharedListService.collection)
        .where('ownerUid', isEqualTo: uid)
        .get();
    // Everything owned, deleted before the user itself: after deleteUser
    // there is no auth left to delete owner-only documents with.
    await _wellness.deleteRemoteAccountData(uid);
    final owned = <DocumentReference<Map<String, dynamic>>>[
      _firestore.collection('users').doc(uid),
      _firestore.collection('bookmarks-v2.0').doc(uid),
      _firestore.collection('named-lists-v1').doc(uid),
      _firestore.collection('recently-watched-v1').doc(uid),
      if (username.isNotEmpty)
        _firestore.collection('usernames').doc(username),
      for (final snapshot in snapshots.docs) snapshot.reference,
    ];
    for (var i = 0; i < owned.length; i += 450) {
      final batch = _firestore.batch();
      for (final reference in owned.skip(i).take(450)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
    try {
      await user.delete();
    } on FirebaseAuthException catch (error) {
      throw TvAccountException(
        code: error.code,
        message: error.message ?? 'Could not delete the account.',
      );
    }
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Best effort only; the Firebase user is already gone.
    }
    await _auth.signOut();
  }
}
