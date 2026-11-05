import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../provider/settings_provider.dart';
import '../../services/auth_navigation_service.dart';
import '../../services/tv_account_service.dart';
import '../app/tv_design.dart';
import '../widgets/tv_choice_row.dart';
import '../widgets/tv_content_row.dart';
import '../widgets/tv_page_header.dart';
import 'tv_account_form_screen.dart';

/// Everything about the signed-in account the TV can change: the profile,
/// the email, the password, or the account itself. Each opens a form.
///
/// Rewritten against FliXtended's Firebase stack: upstream's versions of
/// these screens talked to a Laravel backend (username checks, sign-out
/// everywhere on password change, wallet-credit delete confirms). None of
/// that exists here — profile edits land in the Firestore user document,
/// password changes deliberately sign nothing out anywhere else, and
/// delete is the full wipe with no wallet step.
class TvManageAccountScreen extends StatefulWidget {
  const TvManageAccountScreen({this.service, super.key});

  /// Stands in for Firebase in tests.
  final TvAccountService? service;

  @override
  State<TvManageAccountScreen> createState() => _TvManageAccountScreenState();
}

class _TvManageAccountScreenState extends State<TvManageAccountScreen> {
  final FocusNode _first = FocusNode(debugLabel: 'TV account edit profile');
  late final TvAccountService _service =
      widget.service ?? FirebaseTvAccountService();
  late final Future<TvAccountProfile?> _profile = _service.currentProfile();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _first.context != null) _first.requestFocus();
    });
  }

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  Future<void> _open(Widget page) async {
    final previous = FocusManager.instance.primaryFocus;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && previous?.context != null) previous!.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final palette = TvPalette.of(context);
    return Scaffold(
      backgroundColor: palette.page,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = TvShellMetrics.fromConstraints(constraints);
          final inset = metrics.safeInset + metrics.contentPadding;
          return Padding(
            padding: EdgeInsets.fromLTRB(inset, inset, inset, inset),
            child: FutureBuilder<TvAccountProfile?>(
              future: _profile,
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final rowHeight = TvChoiceRow.heightFor(compact: true);
                Widget row(Widget child) => SizedBox(
                      height: rowHeight,
                      child: child,
                    );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding:
                          const EdgeInsets.only(left: TvDesign.focusOutset + 4),
                      child: TvPageHeader(
                        kicker: tr('tv_account'),
                        title: tr('tv_manage_account'),
                        compact: metrics.compact,
                      ),
                    ),
                    SizedBox(height: metrics.compact ? 18 : 28),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: FocusTraversalGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            row(TvChoiceRow(
                              focusNode: _first,
                              label: tr('edit_profile'),
                              detail: profile == null
                                  ? null
                                  : '${profile.name} · @${profile.username}',
                              leading: Icon(PhosphorIcons.userCircle()),
                              mark: TvChoiceMark.caret,
                              compact: true,
                              onActivate: () => _open(
                                TvEditProfileScreen(service: widget.service),
                              ),
                            )),
                            const SizedBox(height: 6),
                            row(TvChoiceRow(
                              label: tr('change_email'),
                              detail: profile?.email,
                              leading: Icon(PhosphorIcons.at()),
                              mark: TvChoiceMark.caret,
                              compact: true,
                              onActivate: () => _open(
                                TvChangeEmailScreen(service: widget.service),
                              ),
                            )),
                            const SizedBox(height: 6),
                            row(TvChoiceRow(
                              label: tr('change_password'),
                              detail: tr('tv_change_password_detail'),
                              leading: Icon(PhosphorIcons.lockKey()),
                              mark: TvChoiceMark.caret,
                              compact: true,
                              onActivate: () => _open(
                                TvChangePasswordScreen(service: widget.service),
                              ),
                            )),
                            const SizedBox(height: 6),
                            row(TvChoiceRow(
                              label: tr('delete_account'),
                              detail: tr('tv_delete_account_detail'),
                              leading: Icon(PhosphorIcons.trash()),
                              mark: TvChoiceMark.caret,
                              compact: true,
                              onActivate: () => _open(
                                TvDeleteAccountScreen(service: widget.service),
                              ),
                            )),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// The current password, which an account with one has to give; one that
/// only signs in with Google has none to give, and re-authenticates
/// through Google instead (see [FirebaseTvAccountService]).
TvFormFieldSpec _currentPasswordField(bool isGoogleOnly) => TvFormFieldSpec(
      id: 'current',
      label: tr('tv_current_password'),
      icon: PhosphorIcons.lock(),
      secret: true,
      hint: isGoogleOnly ? tr('tv_google_password_hint') : null,
      validate: (value, _) => !isGoogleOnly && value.isEmpty
          ? tr('tv_enter_current_password')
          : null,
    );

void _say(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Name, username and profile picture.
class TvEditProfileScreen extends StatefulWidget {
  const TvEditProfileScreen({this.service, super.key});

  final TvAccountService? service;

  /// The pictures to choose from, as on the phone: 0.png through 144.png.
  static const pictureCount = 145;

  @override
  State<TvEditProfileScreen> createState() => _TvEditProfileScreenState();
}

class _TvEditProfileScreenState extends State<TvEditProfileScreen> {
  late final TvAccountService _service =
      widget.service ?? FirebaseTvAccountService();
  late final Future<TvAccountProfile?> _profile = _service.currentProfile();
  int _profileId = 0;
  bool _pictureChanged = false;
  bool _loaded = false;

  /// The current picture leads the row, so it is in view to start with.
  late List<int> _pictures = <int>[
    for (var id = 0; id < TvEditProfileScreen.pictureCount; id++) id,
  ];

  static final _usernameCharacter = RegExp(r'[a-zA-Z0-9_]');

  void _takeProfile(TvAccountProfile profile) {
    if (_loaded) return;
    _loaded = true;
    _profileId =
        profile.profileId.clamp(0, TvEditProfileScreen.pictureCount - 1);
    _pictures = <int>[
      _profileId,
      for (var id = 0; id < TvEditProfileScreen.pictureCount; id++)
        if (id != _profileId) id,
    ];
  }

  Future<void> _save(Map<String, String> values, TvAccountProfile? user) async {
    final username = values['username']!.trim().toLowerCase();
    if (username != user?.username &&
        !await _service.usernameAvailable(username)) {
      throw const TvAccountException(
        code: 'username-already-in-use',
        message: 'That username is already in use.',
      );
    }
    await _service.updateProfile(
      name: values['name']!.trim(),
      username: username,
      profileId: _profileId,
      // A chosen picture replaces a photo from Google, as on the phone.
      photoUrl: _pictureChanged ? '' : (user?.photoUrl ?? ''),
    );
    if (!mounted) return;
    context.read<SettingsProvider>().analytics.trackProfileUpdated();
    _say(context, tr('tv_profile_updated'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return FutureBuilder<TvAccountProfile?>(
      future: _profile,
      builder: (context, snapshot) {
        // The form captures its fields' initial values once, so it only
        // builds after the profile arrives — never with empty fields.
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user != null) _takeProfile(user);
        return TvAccountFormScreen(
          title: tr('edit_profile'),
          subtitle: tr('tv_edit_profile_subtitle'),
          submitLabel: tr('save'),
          submitIcon: PhosphorIcons.check(),
          onSubmit: (values) => _save(values, user),
          fields: <TvFormFieldSpec>[
            TvFormFieldSpec(
              id: 'name',
              label: tr('full_name'),
              icon: PhosphorIcons.user(),
              initialValue: user?.name ?? '',
              maxLength: 40,
              validate: (value, _) => value.trim().length < 2
                  ? tr('tv_enter_your_full_name')
                  : null,
            ),
            TvFormFieldSpec(
              id: 'username',
              label: tr('username'),
              icon: PhosphorIcons.at(),
              initialValue: user?.username ?? '',
              hint: tr('tv_use_at_least_3_letters_or_numbers'),
              maxLength: 30,
              accepts: _usernameCharacter.hasMatch,
              validate: (value, _) => value.length < 3
                  ? tr('tv_use_at_least_3_letters_or_numbers')
                  : null,
            ),
          ],
          extra: (context, compact) => _PicturePicker(
            pictures: _pictures,
            selected: _profileId,
            compact: compact,
            onSelected: (id) => setState(() {
              _profileId = id;
              _pictureChanged = true;
            }),
          ),
        );
      },
    );
  }
}

/// Every profile picture in one row, the chosen one ringed.
class _PicturePicker extends StatelessWidget {
  const _PicturePicker({
    required this.pictures,
    required this.selected,
    required this.compact,
    required this.onSelected,
  });

  final List<int> pictures;
  final int selected;
  final bool compact;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = TvPalette.of(context);
    final size = compact ? 48.0 : 60.0;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return TvContentRow<int>(
      title: tr('profile_picture'),
      scopeId: 'tv-edit-profile-pictures',
      items: pictures,
      itemId: (id) => '$id',
      semanticLabel: (id) => tr(
        'tv_profile_image_semantics',
        namedArgs: {'number': '${id + 1}'},
      ),
      itemSpacing: 10,
      itemFocusScale: 1.08,
      itemFocusRadius: size,
      onItemActivated: onSelected,
      itemBuilder: (_, id) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: id == selected ? palette.foreground : Colors.transparent,
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/images/profiles/$id.png',
            width: size,
            height: size,
            cacheWidth: (size * ratio).round(),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

/// A new email address, confirmed with the current password — or, for a
/// Google-only account, with a Google sign-in instead (the current
/// password field stays empty then).
class TvChangeEmailScreen extends StatelessWidget {
  const TvChangeEmailScreen({this.service, super.key});

  final TvAccountService? service;

  static bool _emailCharacter(String character) => character.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final service = this.service ?? FirebaseTvAccountService();
    return FutureBuilder<TvAccountProfile?>(
      future: service.currentProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final isGoogleOnly = snapshot.data?.isGoogleOnly ?? false;
        return TvAccountFormScreen(
          title: tr('change_email'),
          subtitle: tr('tv_change_email_subtitle'),
          submitLabel: tr('change_email'),
          submitIcon: PhosphorIcons.at(),
          fields: <TvFormFieldSpec>[
            _currentPasswordField(isGoogleOnly),
            TvFormFieldSpec(
              id: 'email',
              label: tr('tv_new_email'),
              icon: PhosphorIcons.envelopeSimple(),
              accepts: _emailCharacter,
              validate: (value, _) =>
                  !value.contains('@') || !value.contains('.')
                      ? tr('tv_enter_a_valid_email_address')
                      : null,
            ),
            TvFormFieldSpec(
              id: 'repeat',
              label: tr('tv_repeat_new_email'),
              icon: PhosphorIcons.envelopeSimple(),
              accepts: _emailCharacter,
              validate: (value, values) => value.trim().toLowerCase() !=
                      values['email']!.trim().toLowerCase()
                  ? tr('tv_emails_dont_match')
                  : null,
            ),
          ],
          onSubmit: (values) async {
            await service.changeEmail(
              currentPassword: values['current']!,
              email: values['email']!.trim().toLowerCase(),
            );
            if (!context.mounted) return;
            _say(context, tr('tv_email_changed'));
            Navigator.of(context).pop();
          },
        );
      },
    );
  }
}

/// A new password. Firebase does not sign other devices out on a password
/// change, so unlike upstream the TV simply keeps its own session and
/// goes back to Manage account — it does not return to the welcome
/// screen, and the copy here promises nothing about other devices.
class TvChangePasswordScreen extends StatelessWidget {
  const TvChangePasswordScreen({this.service, super.key});

  final TvAccountService? service;

  static const _common = <String>{'123456', '1234567', '12345678', 'password'};

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final service = this.service ?? FirebaseTvAccountService();
    return FutureBuilder<TvAccountProfile?>(
      future: service.currentProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final isGoogleOnly = snapshot.data?.isGoogleOnly ?? false;
        return TvAccountFormScreen(
          title: tr('change_password'),
          subtitle: tr('tv_change_password_subtitle'),
          submitLabel: tr('change_password'),
          submitIcon: PhosphorIcons.lockKey(),
          fields: <TvFormFieldSpec>[
            _currentPasswordField(isGoogleOnly),
            TvFormFieldSpec(
              id: 'password',
              label: tr('tv_new_password'),
              icon: PhosphorIcons.lock(),
              secret: true,
              hint: tr('tv_use_at_least_7_characters'),
              validate: (value, _) => value.length < 7
                  ? tr('tv_use_at_least_7_characters')
                  : _common.contains(value.toLowerCase())
                      ? tr('tv_password_too_common')
                      : null,
            ),
            TvFormFieldSpec(
              id: 'repeat',
              label: tr('tv_repeat_new_password'),
              icon: PhosphorIcons.lock(),
              secret: true,
              validate: (value, values) => value != values['password']
                  ? tr('tv_passwords_dont_match')
                  : null,
            ),
          ],
          onSubmit: (values) async {
            final analytics = context.read<SettingsProvider>().analytics;
            await service.changePassword(
              currentPassword: values['current']!,
              password: values['password']!,
            );
            analytics.trackPasswordChanged();
            if (!context.mounted) return;
            _say(context, tr('tv_password_changed_sign_in'));
            Navigator.of(context).pop();
          },
        );
      },
    );
  }
}

/// Deletes the account for good, once DELETE is typed. There is no second
/// wallet question: FliXtended has no wallet credit to lose, and the
/// delete itself is the full wipe (every owned Firestore document, then
/// the Firebase user). A stale session is refused before anything is
/// deleted — see [FirebaseTvAccountService.deleteAccount].
class TvDeleteAccountScreen extends StatelessWidget {
  const TvDeleteAccountScreen({this.service, super.key});

  final TvAccountService? service;

  static const word = 'DELETE';
  static final _letter = RegExp(r'[a-zA-Z]');

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final service = this.service ?? FirebaseTvAccountService();
    return TvAccountFormScreen(
      title: tr('delete_account'),
      subtitle: tr('tv_delete_account_subtitle'),
      submitLabel: tr('delete_account'),
      submitIcon: PhosphorIcons.trash(),
      fields: <TvFormFieldSpec>[
        TvFormFieldSpec(
          id: 'confirm',
          label: tr('tv_type_delete'),
          icon: PhosphorIcons.textT(),
          hint: tr('tv_type_delete_hint'),
          maxLength: math.max(word.length, 12),
          accepts: _letter.hasMatch,
          validate: (value, _) => value.trim().toUpperCase() != word
              ? tr('tv_must_type_delete')
              : null,
        ),
      ],
      onSubmit: (_) async {
        await service.deleteAccount();
        if (!context.mounted) return;
        final analytics = context.read<SettingsProvider>().analytics;
        analytics.trackAccountDeleted();
        analytics.resetUser();
        _say(context, tr('tv_account_deleted'));
        await AuthNavigationService.returnToSignedOutRoot(context);
      },
    );
  }
}
