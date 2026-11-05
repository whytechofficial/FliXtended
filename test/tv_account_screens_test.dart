import 'package:flixquest/provider/settings_provider.dart';
import 'package:flixquest/services/in_app_messaging_service.dart';
import 'package:flixquest/services/tv_account_service.dart';
import 'package:flixquest/tv/screens/tv_account_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/tv_localization.dart';

const _profile = TvAccountProfile(
  name: 'Aadil Samjeed',
  username: 'aadil',
  email: 'aadil@example.com',
  profileId: 3,
  photoUrl: 'https://example.com/photo.png',
  isGoogleOnly: false,
);

class _FakeService implements TvAccountService {
  _FakeService({this.profile = _profile});

  TvAccountProfile? profile;
  bool usernameFree = true;
  TvAccountException? error;

  final List<String> calls = [];
  String? lastName;
  String? lastUsername;
  int? lastProfileId;
  String? lastPhotoUrl;
  String? lastCurrentPassword;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<TvAccountProfile?> currentProfile() async => profile;

  @override
  Future<bool> usernameAvailable(String username) async => usernameFree;

  @override
  Future<void> updateProfile({
    required String name,
    required String username,
    required int profileId,
    required String photoUrl,
  }) async {
    if (error != null) throw error!;
    calls.add('updateProfile');
    lastName = name;
    lastUsername = username;
    lastProfileId = profileId;
    lastPhotoUrl = photoUrl;
  }

  @override
  Future<void> changeEmail({
    required String currentPassword,
    required String email,
  }) async {
    if (error != null) throw error!;
    calls.add('changeEmail');
    lastCurrentPassword = currentPassword;
    lastEmail = email;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String password,
  }) async {
    if (error != null) throw error!;
    calls.add('changePassword');
    lastCurrentPassword = currentPassword;
    lastPassword = password;
  }

  @override
  Future<void> deleteAccount() async {
    if (error != null) throw error!;
    calls.add('deleteAccount');
  }
}

String? get _focused => FocusManager.instance.primaryFocus?.debugLabel;

/// Opens [page] over a plain home, as the profile does.
Future<void> _pump(WidgetTester tester, Widget page) async {
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

Future<void> _type(WidgetTester tester, String text) async {
  for (final character in text.split('')) {
    final lower = character.toLowerCase();
    if (character != lower) {
      await tester.tap(find.byKey(const ValueKey('tv-form-key-shift')));
      await tester.pump();
    }
    final id = character == ' ' ? 'space' : lower;
    await tester.tap(find.byKey(ValueKey('tv-form-key-$id')));
    await tester.pump();
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _key(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('tv-form-key-$id')));
  await _settle(tester);
}

void main() {
  initializeTvTranslations();

  testWidgets('the manage screen lists every change with the profile details',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, TvManageAccountScreen(service: service));
    expect(find.text('Aadil Samjeed · @aadil'), findsOneWidget);
    expect(find.text('aadil@example.com'), findsOneWidget);
    for (final label in <String>[
      'Edit profile',
      'Change email',
      'Change password',
      'Delete account',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(_focused, 'TV account edit profile');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(TvChangePasswordScreen), findsOneWidget);
  });

  testWidgets('editing the profile saves the name and the picture chosen',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, TvEditProfileScreen(service: service));
    expect(find.text('Aadil Samjeed'), findsOneWidget);
    expect(find.text('aadil'), findsOneWidget);

    await _key(tester, 'clear');
    await _type(tester, 'Aadil S');
    // Picked as the remote would reach it: scrolled into the row's view.
    final picture = find.byKey(const ValueKey('tv-edit-profile-pictures:5'));
    await tester.ensureVisible(picture);
    await tester.pumpAndSettle();
    await tester.tap(picture);
    await tester.pumpAndSettle();
    expect(find.text('Aadil S'), findsOneWidget);

    // Next to the username, then Save from the last field.
    await _key(tester, 'action');
    await _key(tester, 'action');

    expect(service.calls, <String>['updateProfile']);
    expect(service.lastName, 'Aadil S');
    expect(service.lastUsername, 'aadil');
    expect(service.lastProfileId, 5);
    expect(service.lastPhotoUrl, '');
    expect(find.byType(TvEditProfileScreen), findsNothing);
    expect(find.text('Profile updated'), findsOneWidget);
  });

  testWidgets('a username someone else has is refused before saving',
      (tester) async {
    final service = _FakeService()..usernameFree = false;
    await _pump(tester, TvEditProfileScreen(service: service));
    await _key(tester, 'action');
    await _type(tester, '2');
    await _key(tester, 'action');

    expect(find.text('That username is already in use.'), findsOneWidget);
    expect(service.calls, isEmpty);
    expect(find.byType(TvEditProfileScreen), findsOneWidget);
  });

  testWidgets(
      'changing the password checks the repeat, then pops with it changed',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, TvChangePasswordScreen(service: service));

    await _type(tester, 'secret123');
    await _key(tester, 'action');
    await _type(tester, 'newsecret1');
    await _key(tester, 'action');
    await _type(tester, 'newsecret2');
    await _key(tester, 'action');
    expect(find.text("The passwords don't match."), findsOneWidget);
    expect(service.calls, isEmpty, reason: 'nothing sent');

    await _key(tester, 'delete');
    await _type(tester, '1');
    await _key(tester, 'action');

    expect(service.calls, <String>['changePassword']);
    expect(service.lastCurrentPassword, 'secret123');
    expect(service.lastPassword, 'newsecret1');
    // Firebase signs nothing out anywhere else: the TV keeps its session
    // and returns to where it was, not to a welcome screen.
    expect(find.byType(TvChangePasswordScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Password changed.'), findsOneWidget);
  });

  testWidgets('a wrong current password shows the friendly message',
      (tester) async {
    final service = _FakeService()
      ..error = const TvAccountException(
        code: 'wrong-password',
        message: 'The password is invalid.',
      );
    await _pump(tester, TvChangeEmailScreen(service: service));

    await _type(tester, 'wrong');
    await _key(tester, 'action');
    await _type(tester, 'new@example.com');
    await _key(tester, 'action');
    await _type(tester, 'new@example.com');
    await _key(tester, 'action');

    expect(
      find.text('The email or password is incorrect.'),
      findsOneWidget,
    );
    expect(find.byType(TvChangeEmailScreen), findsOneWidget);
    expect(_focused, isNotNull);
  });

  testWidgets('changing the email sends the new address', (tester) async {
    final service = _FakeService();
    await _pump(tester, TvChangeEmailScreen(service: service));

    await _type(tester, 'secret123');
    await _key(tester, 'action');
    await _type(tester, 'New@example.com');
    await _key(tester, 'action');
    await _type(tester, 'other@example.com');
    await _key(tester, 'action');
    expect(find.text("The email addresses don't match."), findsOneWidget);

    await _key(tester, 'clear');
    await _type(tester, 'new@example.com');
    await _key(tester, 'action');

    expect(service.calls, <String>['changeEmail']);
    expect(service.lastCurrentPassword, 'secret123');
    expect(service.lastEmail, 'new@example.com');
    expect(find.byType(TvChangeEmailScreen), findsNothing);
    expect(find.text('Email changed. Check your inbox to verify it.'),
        findsOneWidget);
  });

  testWidgets('a Google-only account changes email without a password',
      (tester) async {
    final service = _FakeService(
      profile: const TvAccountProfile(
        name: 'Aadil Samjeed',
        username: 'aadil',
        email: 'aadil@example.com',
        profileId: 3,
        photoUrl: '',
        isGoogleOnly: true,
      ),
    );
    await _pump(tester, TvChangeEmailScreen(service: service));
    expect(find.text('Leave it empty if you only sign in with Google.'),
        findsOneWidget);

    // The empty current-password field passes validation for Google-only
    // accounts, so the first action key moves straight to the new email.
    await _key(tester, 'action');
    await _type(tester, 'new@example.com');
    await _key(tester, 'action');
    await _type(tester, 'new@example.com');
    await _key(tester, 'action');

    expect(service.calls, <String>['changeEmail']);
    expect(service.lastCurrentPassword, '');
    expect(service.lastEmail, 'new@example.com');
    expect(find.byType(TvChangeEmailScreen), findsNothing);
  });

  testWidgets('deleting asks for DELETE, then wipes and signs out',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, TvDeleteAccountScreen(service: service));

    await _type(tester, 'delet');
    await _key(tester, 'action');
    expect(find.text('Type DELETE to confirm.'), findsWidgets);
    expect(service.calls, isEmpty);

    await _type(tester, 'e');
    await _key(tester, 'action');

    expect(service.calls, <String>['deleteAccount']);
    expect(find.byType(TvDeleteAccountScreen), findsNothing);
    expect(find.text('Your account was deleted'), findsOneWidget);
  });

  testWidgets('a stale session refuses the delete before anything is wiped',
      (tester) async {
    final service = _FakeService()
      ..error = const TvAccountException(
        code: 'requires-recent-login',
        message: 'Sign in again before deleting.',
      );
    await _pump(tester, TvDeleteAccountScreen(service: service));

    await _type(tester, 'DELETE');
    await _key(tester, 'action');

    expect(
      find.text(
        'For security, sign out and sign in again, then delete your account.',
      ),
      findsOneWidget,
    );
    expect(service.calls, isEmpty);
    expect(find.byType(TvDeleteAccountScreen), findsOneWidget);
  });
}
