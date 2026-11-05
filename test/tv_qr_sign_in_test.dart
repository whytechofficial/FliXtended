import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flixquest/provider/settings_provider.dart';
import 'package:flixquest/screens/common/tv_sign_in_approval_screen.dart';
import 'package:flixquest/services/in_app_messaging_service.dart';
import 'package:flixquest/services/tv_qr_sign_in_service.dart';
import 'package:flixquest/tv/screens/tv_phone_sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/tv_localization.dart';

TvQrSignInCode _code({
  String codeId = 'code-1',
  String shortCode = 'BCDFGHJK',
  Duration? expiresIn,
}) =>
    TvQrSignInCode(
      codeId: codeId,
      shortCode: shortCode,
      deviceSecret: 'device-secret',
      expiresAt: DateTime.now().add(expiresIn ?? const Duration(minutes: 10)),
      interval: const Duration(seconds: 5),
    );

class _FakeService implements TvQrSignInService {
  _FakeService({this.configured = true, this.uid = 'phone-uid'});

  bool configured;
  String? uid;

  @override
  bool get isWorkerConfigured => configured;

  @override
  String? get currentUid => uid;

  TvQrSignInCode Function()? startNext;
  TvQrSignInException? startError;
  final List<TvQrSignInCheck Function()> pollScript = [];
  final List<String> polls = [];
  int starts = 0;
  String? approvedId;
  String? deniedId;
  TvQrApprovalRequest? lookupResult;
  TvQrSignInException? lookupError;

  @override
  Future<TvQrSignInCode> startSignIn() async {
    starts++;
    if (startError != null) throw startError!;
    return startNext != null ? startNext!() : _code();
  }

  @override
  Future<TvQrSignInCheck> checkSignIn(TvQrSignInCode code) async {
    polls.add(code.codeId);
    if (pollScript.isEmpty) {
      return const TvQrSignInCheck(TvQrSignInStatus.pending);
    }
    return pollScript.removeAt(0)();
  }

  @override
  Future<TvQrApprovalRequest> findPendingCode(String typedCode) async {
    if (lookupError != null) throw lookupError!;
    return lookupResult ??
        TvQrApprovalRequest(
          codeId: 'code-1',
          shortCode: 'BCDFGHJK',
          expiresAt: DateTime.now().add(const Duration(minutes: 9)),
        );
  }

  @override
  Future<void> approveCode(String codeId) async {
    approvedId = codeId;
  }

  @override
  Future<void> denyCode(String codeId) async {
    deniedId = codeId;
  }
}

/// A fake for the real service's code store: records clash checks and
/// created documents, and can fail the clash check on demand.
class _FakeCodeStore implements TvQrSignInCodeStore {
  _FakeCodeStore({
    List<bool> clashResults = const <bool>[],
    this.clashError,
  }) : _clashResults = List<bool>.of(clashResults);

  final List<bool> _clashResults;
  final FirebaseException? clashError;
  int clashChecks = 0;
  final List<Map<String, dynamic>> created = <Map<String, dynamic>>[];

  @override
  Future<bool> hasPendingCode(String shortCode) async {
    clashChecks++;
    if (clashError != null) throw clashError!;
    if (_clashResults.isEmpty) return false;
    return _clashResults.removeAt(0);
  }

  @override
  Future<String> createPendingCode(Map<String, dynamic> data) async {
    created.add(data);
    return 'code-${created.length}';
  }
}

Future<void> _pumpTv(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => SettingsProvider(),
    child: MaterialApp(
      navigatorKey: InAppMessagingService.navigatorKey,
      home: const Scaffold(body: Text('home')),
    ),
  ));
  InAppMessagingService.navigatorKey.currentState!
      .push(MaterialPageRoute<void>(builder: (_) => page));
  await tester.pumpAndSettle();
}

Future<void> _pumpPhone(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

/// Leaves a TV screen that is still polling: popping disposes it, and
/// pumping past one interval lets its wait loop notice and stop, so no
/// timer is left pending at the test's end.
Future<void> _leaveTv(WidgetTester tester) async {
  InAppMessagingService.navigatorKey.currentState!.pop();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  initializeTvTranslations();

  test('short codes normalize the way viewers type them', () {
    expect(normalizeTvShortCode('bcdf-ghjk'), 'BCDFGHJK');
    expect(normalizeTvShortCode(' BCDF GHJK '), 'BCDFGHJK');
    expect(normalizeTvShortCode('BCDFGHJK'), 'BCDFGHJK');
  });

  test('a code shows itself dashed and knows when it expired', () {
    final code = _code();
    expect(code.displayCode, 'BCDF-GHJK');
    expect(code.isExpired, isFalse);
    expect(_code(expiresIn: const Duration(seconds: -1)).isExpired, isTrue);
  });

  // Regression for the Nov 5 MEmu failure: the TV is signed out on the
  // phone-sign-in screen, and the published rules only let a signed-in
  // user read tv-sign-in-codes, so the old clash-check query failed
  // permission-denied on every attempt and no code was ever created.
  // These tests drive the real startSignIn through a fake store, so
  // they need no Firebase app.
  test('startSignIn succeeds while signed out without a clash check',
      () async {
    final store = _FakeCodeStore();
    final service = FirebaseTvQrSignInService(
      codeStore: store,
      isSignedIn: () => false,
    );
    final code = await service.startSignIn();
    expect(store.clashChecks, 0);
    expect(store.created, hasLength(1));
    expect(store.created.single['status'], 'pending');
    expect(store.created.single['shortCode'], code.shortCode);
    expect(code.codeId, 'code-1');
    expect(code.shortCode.length, 8);
    expect(code.isExpired, isFalse);
  });

  test(
      'startSignIn falls through to create when a signed-in clash check is permission-denied',
      () async {
    final store = _FakeCodeStore(
      clashError: FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ),
    );
    final service = FirebaseTvQrSignInService(
      codeStore: store,
      isSignedIn: () => true,
    );
    final code = await service.startSignIn();
    expect(store.clashChecks, 1);
    expect(store.created, hasLength(1));
    expect(code.codeId, 'code-1');
  });

  test('startSignIn still redraws on a clash while signed in', () async {
    final store = _FakeCodeStore(clashResults: <bool>[true, false]);
    final service = FirebaseTvQrSignInService(
      codeStore: store,
      isSignedIn: () => true,
    );
    final code = await service.startSignIn();
    expect(store.clashChecks, 2);
    expect(store.created, hasLength(1));
    expect(code.shortCode, store.created.single['shortCode']);
  });

  test('startSignIn surfaces a non-permission clash-check failure',
      () async {
    final store = _FakeCodeStore(
      clashError: FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      ),
    );
    final service = FirebaseTvQrSignInService(
      codeStore: store,
      isSignedIn: () => true,
    );
    await expectLater(
      service.startSignIn(),
      throwsA(isA<FirebaseException>()
          .having((error) => error.code, 'code', 'unavailable')),
    );
    expect(store.created, isEmpty);
  });

  testWidgets('the TV shows its code and keeps waiting while pending',
      (tester) async {
    final service = _FakeService();
    await _pumpTv(tester, TvPhoneSignInScreen(service: service));
    expect(find.text('BCDF-GHJK'), findsOneWidget);
    expect(find.text('Sign in with your phone'), findsOneWidget);
    expect(find.text('Approve it on your phone'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(service.polls, ['code-1']);
    expect(find.text('BCDF-GHJK'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _leaveTv(tester);
  });

  testWidgets('sustained poll failures show the outage error and Retry',
      (tester) async {
    final service = _FakeService();
    // Three failed polls in a row: the first two stay silent, the third
    // surfaces the outage error. Later polls succeed again.
    service.pollScript.addAll(<TvQrSignInCheck Function()>[
      () => throw Exception('worker down'),
      () => throw Exception('worker down'),
      () => throw Exception('worker down'),
    ]);
    await _pumpTv(tester, TvPhoneSignInScreen(service: service));
    await tester.pump(const Duration(seconds: 6));
    expect(service.polls, ['code-1']);
    expect(find.text("Couldn't reach the sign-in service — retrying…"),
        findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(service.polls, ['code-1', 'code-1']);
    expect(find.text("Couldn't reach the sign-in service — retrying…"),
        findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(service.polls, ['code-1', 'code-1', 'code-1']);
    expect(find.text("Couldn't reach the sign-in service — retrying…"),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // Retry restarts the wait for the same code; the next poll succeeds
    // (the script is spent, so the fake answers pending) and clears it.
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(seconds: 6));
    expect(service.polls.length, 4);
    expect(find.text("Couldn't reach the sign-in service — retrying…"),
        findsNothing);
    expect(find.text('BCDF-GHJK'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _leaveTv(tester);
  });

  testWidgets('an approval signs the TV in and returns to the app root',
      (tester) async {
    final service = _FakeService();
    service.pollScript.add(
        () => const TvQrSignInCheck(TvQrSignInStatus.approved, 'tv-uid'));
    await _pumpTv(tester, TvPhoneSignInScreen(service: service));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a denial shows a new code with the denial notice',
      (tester) async {
    final service = _FakeService();
    service.pollScript
        .add(() => const TvQrSignInCheck(TvQrSignInStatus.denied));
    service.startNext = () => _code(codeId: 'code-2', shortCode: 'QRSTUVWX');
    await _pumpTv(tester, TvPhoneSignInScreen(service: service));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('QRST-UVWX'), findsOneWidget);
    expect(
        find.text('The sign-in was cancelled on the phone. Here is a new code.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await _leaveTv(tester);
  });

  testWidgets('an expiry shows a new code with the expiry notice',
      (tester) async {
    final service = _FakeService();
    service.pollScript
        .add(() => const TvQrSignInCheck(TvQrSignInStatus.expired));
    service.startNext = () => _code(codeId: 'code-2', shortCode: 'QRSTUVWX');
    await _pumpTv(tester, TvPhoneSignInScreen(service: service));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('QRST-UVWX'), findsOneWidget);
    expect(find.text('That code expired. Here is a new one.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _leaveTv(tester);
  });

  testWidgets('leaving the screen stops polling', (tester) async {
    final service = _FakeService();
    await _pumpTv(tester, TvPhoneSignInScreen(service: service));
    await tester.pump(const Duration(seconds: 6));
    final pollsWhileShown = service.polls.length;
    expect(pollsWhileShown, greaterThan(0));
    // Pop back to home: the screen disposes and its generation bumps.
    // (No AppBar back button exists on the TV screen, so pop directly.)
    InAppMessagingService.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(service.polls.length, pollsWhileShown);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unconfigured Worker shows the setup message, no code',
      (tester) async {
    final service = _FakeService(configured: false);
    await _pumpTv(tester, TvPhoneSignInScreen(service: service));
    expect(
        find.text(
            "Phone sign-in isn't set up yet. Use the remote for now."),
        findsOneWidget);
    expect(service.starts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signed-out phone sees only the sign-in requirement',
      (tester) async {
    final service = _FakeService(uid: null);
    await _pumpPhone(
        tester, TvSignInApprovalScreen(service: service));
    expect(find.text('Sign in on this phone first to approve a TV.'),
        findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a typed code can be found and approved', (tester) async {
    final service = _FakeService();
    await _pumpPhone(
        tester, TvSignInApprovalScreen(service: service));
    await tester.enterText(find.byType(TextField), 'bcdf-ghjk');
    await tester.tap(find.text('Find TV'));
    await tester.pumpAndSettle();
    expect(find.text('A TV is asking to sign in as you. Approve it?'),
        findsOneWidget);
    // Twice: once in the code field, once on the found card.
    expect(find.text('BCDF-GHJK'), findsNWidgets(2));
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(service.approvedId, 'code-1');
    expect(find.text('TV signed in. You can close this screen.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a code nothing waits on says so', (tester) async {
    final service = _FakeService();
    service.lookupError = const TvQrSignInException(
        code: 'not-found', message: 'No pending code matches.');
    await _pumpPhone(
        tester, TvSignInApprovalScreen(service: service));
    await tester.enterText(find.byType(TextField), 'ZZZZ-ZZZZ');
    await tester.tap(find.text('Find TV'));
    await tester.pumpAndSettle();
    expect(
        find.text('No TV is waiting with that code. Check it and try again.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('declining a code denies it', (tester) async {
    final service = _FakeService();
    await _pumpPhone(
        tester, TvSignInApprovalScreen(service: service));
    await tester.enterText(find.byType(TextField), 'BCDF-GHJK');
    await tester.tap(find.text('Find TV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(service.deniedId, 'code-1');
    expect(find.text('Sign-in declined.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
