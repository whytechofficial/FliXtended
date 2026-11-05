import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// The Cloudflare Worker endpoint the TV polls for its sign-in token.
///
/// REPLACE THIS with the URL of the deployed Worker from
/// `flixtended-merge-scope/beta61-qr-worker/` before QR sign-in can work.
/// Until it is replaced, the TV sign-in screen says phone sign-in is not
/// set up yet instead of polling a dead address.
const _tvQrSignInWorkerUrlPlaceholder =
    'https://YOUR-TV-SIGN-IN-WORKER.workers.dev/tv-sign-in/poll';

const tvQrSignInWorkerUrl =
    'https://flixtended-tv-sign-in.aadilsamjeed.workers.dev/tv-sign-in/poll';

/// True once [tvQrSignInWorkerUrl] points at a real Worker.
bool get tvQrSignInWorkerConfigured =>
    tvQrSignInWorkerUrl != _tvQrSignInWorkerUrlPlaceholder;

/// What a QR sign-in failure means: a stable [code] the screens map to
/// their own words, plus the raw [message] as a fallback.
class TvQrSignInException implements Exception {
  const TvQrSignInException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'TvQrSignInException($code): $message';
}

/// A code the TV shows, as text and as a QR code, so a phone can sign it
/// in. [codeId] and [deviceSecret] stay on the TV: only the TV that
/// created the code can redeem the phone's approval.
class TvQrSignInCode {
  const TvQrSignInCode({
    required this.codeId,
    required this.shortCode,
    required this.deviceSecret,
    required this.expiresAt,
    required this.interval,
  });

  /// The Firestore document id of the code.
  final String codeId;

  /// The code as the phone types it, without the dash: BCDFGHJK.
  final String shortCode;

  /// Random secret only this TV knows; the Worker checks it before
  /// handing out a token, so a short-code guesser who finds the code
  /// document cannot redeem somebody else's approval.
  final String deviceSecret;
  final DateTime expiresAt;

  /// How long the TV waits between checks.
  final Duration interval;

  /// The short code as displayed, with a dash in the middle.
  String get displayCode =>
      '${shortCode.substring(0, 4)}-${shortCode.substring(4)}';

  /// What the QR code carries: just the short code. A camera shows it as
  /// text, and the viewer types it into the phone app under "Sign in a
  /// TV" — no verification website is involved.
  String get qrData => shortCode;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

enum TvQrSignInStatus { pending, approved, denied, expired, consumed }

/// One check on a [TvQrSignInCode].
class TvQrSignInCheck {
  const TvQrSignInCheck(this.status, [this.signedInUid]);

  final TvQrSignInStatus status;

  /// The Firebase uid the TV signed in as, once approved.
  final String? signedInUid;
}

/// A TV waiting for approval, as the phone sees it.
class TvQrApprovalRequest {
  const TvQrApprovalRequest({
    required this.codeId,
    required this.shortCode,
    required this.expiresAt,
  });

  final String codeId;
  final String shortCode;
  final DateTime expiresAt;

  String get displayCode =>
      '${shortCode.substring(0, 4)}-${shortCode.substring(4)}';

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// The QR sign-in handshake against FliXtended's Firebase stack (not
/// upstream's Laravel device flow): codes live in the `tv-sign-in-codes`
/// collection, the phone approves in Firestore, and a Cloudflare Worker
/// holding a Firebase Admin service account mints the custom token the
/// TV signs in with.
/// The short code as the viewer types it, dash or no dash, any case,
/// reduced to the form stored in Firestore.
String normalizeTvShortCode(String typed) =>
    typed.trim().toUpperCase().replaceAll('-', '').replaceAll(' ', '');

abstract class TvQrSignInService {
  /// False while the Worker URL is still the placeholder: the screen
  /// then says phone sign-in is not set up yet instead of polling a
  /// dead address.
  bool get isWorkerConfigured;

  /// The signed-in phone user's uid, or null when the phone is signed
  /// out. The approval screen reads this instead of touching Firebase
  /// Auth directly, so it stays testable.
  String? get currentUid;

  /// Creates a fresh code for the TV to show. The TV is signed out at
  /// this point, so creation is unauthenticated and shape-validated by
  /// the Firestore rules (see beta61-qr-worker/firestore-rules-snippet).
  Future<TvQrSignInCode> startSignIn();

  /// One poll of the Worker for [code]'s outcome. On approval this also
  /// signs the TV in with the minted custom token.
  Future<TvQrSignInCheck> checkSignIn(TvQrSignInCode code);

  /// Finds a pending code by the short code the viewer typed, dash or
  /// no dash, any case.
  Future<TvQrApprovalRequest> findPendingCode(String typedCode);

  /// Approves [codeId] as the currently signed-in phone user.
  Future<void> approveCode(String codeId);

  /// Turns [codeId] down as the currently signed-in phone user.
  Future<void> denyCode(String codeId);
}

/// The characters a short code uses: no 0/O or 1/I/L, so a code read off
/// a TV screen cannot be misread.
const _shortCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// The Firestore operations [FirebaseTvQrSignInService.startSignIn]
/// needs, behind a seam tests can fake: the real Firestore types cannot
/// be constructed in a unit test (private constructors, and they need a
/// Firebase app), so the service takes this store instead of touching
/// Firestore directly for code creation. Production uses the
/// Firestore-backed implementation below.
abstract class TvQrSignInCodeStore {
  /// True when a pending code with [shortCode] already exists.
  Future<bool> hasPendingCode(String shortCode);

  /// Creates a pending code document from [data] and returns its id.
  Future<String> createPendingCode(Map<String, dynamic> data);
}

class _FirestoreTvQrSignInCodeStore implements TvQrSignInCodeStore {
  _FirestoreTvQrSignInCodeStore(this.codes);

  final CollectionReference<Map<String, dynamic>> codes;

  @override
  Future<bool> hasPendingCode(String shortCode) async {
    final clash = await codes
        .where('shortCode', isEqualTo: shortCode)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    return clash.docs.isNotEmpty;
  }

  @override
  Future<String> createPendingCode(Map<String, dynamic> data) async {
    final doc = codes.doc();
    await doc.set(data);
    return doc.id;
  }
}

class FirebaseTvQrSignInService implements TvQrSignInService {
  FirebaseTvQrSignInService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? httpClient,
    String workerUrl = tvQrSignInWorkerUrl,
    // Test seams: when set, startSignIn uses [codeStore] instead of
    // Firestore and trusts [isSignedIn] instead of Firebase Auth, so a
    // test can construct the service without a Firebase app. Production
    // leaves both unset.
    TvQrSignInCodeStore? codeStore,
    bool Function()? isSignedIn,
  })  : _firestore = firestore,
        _auth = auth,
        _http = httpClient ?? http.Client(),
        _workerUrl = workerUrl,
        _codeStore = codeStore,
        _isSignedIn = isSignedIn;

  // Nullable on purpose: the Firebase singletons are resolved lazily
  // below, so constructing the service (e.g. in a test with a fake
  // store) does not require an initialized Firebase app.
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  final http.Client _http;
  final String _workerUrl;
  final TvQrSignInCodeStore? _codeStore;
  final bool Function()? _isSignedIn;

  FirebaseFirestore get _firestoreResolved =>
      _firestore ?? FirebaseFirestore.instance;

  FirebaseAuth get _authResolved => _auth ?? FirebaseAuth.instance;

  @override
  bool get isWorkerConfigured =>
      _workerUrl != _tvQrSignInWorkerUrlPlaceholder;

  @override
  String? get currentUid => _authResolved.currentUser?.uid;

  static const _collection = 'tv-sign-in-codes';

  /// How long a code lives before the TV must show a new one.
  static const codeLifetime = Duration(minutes: 10);

  /// How long the TV waits between Worker checks.
  static const pollInterval = Duration(seconds: 5);

  CollectionReference<Map<String, dynamic>> get _codes =>
      _firestoreResolved.collection(_collection);

  static String _randomShortCode(Random random) {
    final chars = List<String>.generate(
      8,
      (_) => _shortCodeAlphabet[random.nextInt(_shortCodeAlphabet.length)],
    );
    return chars.join();
  }

  static String _randomSecret(Random random) {
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _hashSecret(String secret) =>
      sha256.convert(utf8.encode(secret)).toString();

  @override
  Future<TvQrSignInCode> startSignIn() async {
    final random = Random.secure();
    final store = _codeStore ?? _FirestoreTvQrSignInCodeStore(_codes);
    // The TV is signed out on the phone-sign-in screen, and the
    // published rules only let a signed-in user READ tv-sign-in-codes
    // — so a clash check here used to fail permission-denied on every
    // attempt and the screen never reached the create, which is open
    // and shape-validated. Skip the check while signed out, and if a
    // signed-in caller's check is denied anyway, fall through to the
    // create instead of failing the whole attempt. No rules change.
    final signedIn = _isSignedIn?.call() ?? _authResolved.currentUser != null;
    // A collision is near-impossible (32^8 codes), but a pending code
    // with the same short code would let a phone approve the wrong TV,
    // so a clash means drawing again.
    for (var attempt = 0; attempt < 5; attempt++) {
      final shortCode = _randomShortCode(random);
      if (signedIn) {
        try {
          if (await store.hasPendingCode(shortCode)) continue;
        } on FirebaseException catch (error) {
          if (error.code != 'permission-denied') rethrow;
        }
      }
      final deviceSecret = _randomSecret(random);
      final expiresAt = DateTime.now().add(codeLifetime);
      final codeId = await store.createPendingCode(<String, dynamic>{
        'shortCode': shortCode,
        'deviceSecretHash': _hashSecret(deviceSecret),
        'status': 'pending',
        'expiresAt': Timestamp.fromDate(expiresAt),
        'approvedUid': null,
        'approvedAt': null,
        'consumed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return TvQrSignInCode(
        codeId: codeId,
        shortCode: shortCode,
        deviceSecret: deviceSecret,
        expiresAt: expiresAt,
        interval: pollInterval,
      );
    }
    throw const TvQrSignInException(
      code: 'code-collision',
      message: 'Could not draw a fresh sign-in code.',
    );
  }

  @override
  Future<TvQrSignInCheck> checkSignIn(TvQrSignInCode code) async {
    if (code.isExpired) {
      return const TvQrSignInCheck(TvQrSignInStatus.expired);
    }
    late final http.Response response;
    try {
      response = await _http.post(
        Uri.parse(_workerUrl),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{
          'codeId': code.codeId,
          'deviceSecret': code.deviceSecret,
        }),
      );
    } catch (error) {
      throw TvQrSignInException(code: 'network', message: '$error');
    }
    if (response.statusCode != 200) {
      throw TvQrSignInException(
        code: 'worker-error',
        message: 'Worker answered ${response.statusCode}.',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const TvQrSignInException(
        code: 'bad-response',
        message: 'Worker answer was not an object.',
      );
    }
    switch (body['status']) {
      case 'pending':
        return const TvQrSignInCheck(TvQrSignInStatus.pending);
      case 'denied':
        return const TvQrSignInCheck(TvQrSignInStatus.denied);
      case 'expired':
      case 'consumed':
        // A consumed code is spent: the TV shows a fresh one rather than
        // standing on a code that can never sign it in.
        return const TvQrSignInCheck(TvQrSignInStatus.expired);
      case 'approved':
        final token = body['customToken'];
        if (token is! String || token.isEmpty) {
          throw const TvQrSignInException(
            code: 'missing-token',
            message: 'Worker approved without a token.',
          );
        }
        final credential = await _authResolved.signInWithCustomToken(token);
        final uid = credential.user?.uid;
        if (uid == null) {
          throw const TvQrSignInException(
            code: 'sign-in-failed',
            message: 'Custom-token sign-in returned no user.',
          );
        }
        return TvQrSignInCheck(TvQrSignInStatus.approved, uid);
      default:
        throw TvQrSignInException(
          code: 'bad-status',
          message: 'Unknown Worker status: ${body['status']}.',
        );
    }
  }

  @override
  Future<TvQrApprovalRequest> findPendingCode(String typedCode) async {
    final shortCode = normalizeTvShortCode(typedCode);
    if (shortCode.length != 8) {
      throw const TvQrSignInException(
        code: 'not-found',
        message: 'That code is not 8 characters.',
      );
    }
    late final QuerySnapshot<Map<String, dynamic>> found;
    try {
      found = await _codes
          .where('shortCode', isEqualTo: shortCode)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
    } on FirebaseException catch (error) {
      throw TvQrSignInException(code: _mapCode(error), message: '$error');
    }
    if (found.docs.isEmpty) {
      throw const TvQrSignInException(
        code: 'not-found',
        message: 'No pending code matches.',
      );
    }
    final doc = found.docs.single;
    final data = doc.data();
    final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
    final request = TvQrApprovalRequest(
      codeId: doc.id,
      shortCode: (data['shortCode'] as String?) ?? shortCode,
      expiresAt: expiresAt ?? DateTime.now(),
    );
    if (request.isExpired) {
      throw const TvQrSignInException(
        code: 'expired',
        message: 'That code already expired.',
      );
    }
    return request;
  }

  Future<void> _decide(String codeId, String status) async {
    final user = _authResolved.currentUser;
    if (user == null) {
      throw const TvQrSignInException(
        code: 'signed-out',
        message: 'No phone user is signed in.',
      );
    }
    try {
      await _codes.doc(codeId).update(<String, dynamic>{
        'status': status,
        'approvedUid': user.uid,
        'approvedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      // The rules only let a pending code flip to approved/denied, so a
      // refusal here means the code moved on already.
      throw TvQrSignInException(code: _mapCode(error), message: '$error');
    }
  }

  @override
  Future<void> approveCode(String codeId) => _decide(codeId, 'approved');

  @override
  Future<void> denyCode(String codeId) => _decide(codeId, 'denied');

  static String _mapCode(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'already-resolved';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'network';
      default:
        return error.code;
    }
  }
}
