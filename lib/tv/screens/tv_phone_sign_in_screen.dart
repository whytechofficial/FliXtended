import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../provider/settings_provider.dart';
import '../../services/auth_navigation_service.dart';
import '../../services/tv_qr_sign_in_service.dart';
import '../app/tv_design.dart';
import '../widgets/tv_pill_button.dart';
import 'tv_auth_screen.dart';

/// Signing the TV in from a phone, the way YouTube's TV app does: the QR
/// code shows the short code, the viewer enters it in the phone app under
/// "Sign in a TV" and approves, and this screen signs in by itself once
/// the phone approves. Nothing is typed with the remote.
///
/// Adapted from upstream's phone sign-in screen against FliXtended's
/// Firebase stack: there is no Laravel device flow here. The TV creates
/// a code document in Firestore, the phone approves it there, and a
/// Cloudflare Worker mints the custom token the TV signs in with. There
/// are no device limits to pick from, and the existing TV auth screen
/// is left exactly as it is — this is a separate screen.
///
/// The screen checks back every few seconds and takes a new code
/// whenever one expires or is turned down on the phone.
class TvPhoneSignInScreen extends StatefulWidget {
  const TvPhoneSignInScreen({this.service, super.key});

  /// Stands in for Firestore and the Worker in tests.
  final TvQrSignInService? service;

  @override
  State<TvPhoneSignInScreen> createState() => _TvPhoneSignInScreenState();
}

class _TvPhoneSignInScreenState extends State<TvPhoneSignInScreen> {
  late final TvQrSignInService _service =
      widget.service ?? FirebaseTvQrSignInService();
  TvQrSignInCode? _code;
  String? _problem;
  String? _notice;
  bool _signingIn = false;

  /// Consecutive failed polls. A blip or two stays silent, as before;
  /// a sustained outage surfaces instead of retrying forever unnoticed
  /// (a Worker 500 once hid behind this silence for hours).
  int _pollFailures = 0;

  /// True while the sustained-outage error is showing.
  bool _pollError = false;

  /// Poll failures in a row before the outage error shows.
  static const int _pollErrorThreshold = 3;

  /// Bumped for each code and on dispose, so a superseded wait stops.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (_service.isWorkerConfigured) {
      _newCode();
    } else {
      // The Worker URL is still the placeholder: polling would only
      // fail, so say so plainly instead of showing a dead code.
      _problem = tr('tv_phone_sign_in_not_configured');
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _newCode({String? notice}) async {
    final generation = ++_generation;
    setState(() {
      _code = null;
      _problem = null;
      _notice = notice;
      _pollFailures = 0;
      _pollError = false;
    });
    try {
      final code = await _service.startSignIn();
      if (!mounted || generation != _generation) return;
      setState(() => _code = code);
      unawaited(_waitForPhone(code, generation));
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _problem = tr('tv_phone_sign_in_failed'));
      }
    }
  }

  /// Retries polling for the same code right now, instead of waiting for
  /// the next interval. The running wait is stopped first, so only one
  /// poll loop ever runs for a code.
  void _retryPoll() {
    final code = _code;
    if (code == null || _signingIn) return;
    final generation = ++_generation;
    setState(() {
      _notice = null;
      _pollFailures = 0;
      _pollError = false;
    });
    unawaited(_waitForPhone(code, generation));
  }

  /// Checks one at a time until the phone answers, the code expires, or
  /// this screen (or its code) goes away.
  Future<void> _waitForPhone(TvQrSignInCode code, int generation) async {
    bool current() => mounted && generation == _generation;
    while (true) {
      await Future<void>.delayed(code.interval);
      if (!current()) return;
      TvQrSignInCheck check;
      try {
        check = await _service.checkSignIn(code);
      } catch (_) {
        // A blip or two passes silently, as before. A sustained outage
        // surfaces: the screen says the service cannot be reached and
        // keeps retrying, with a Retry button for an immediate attempt.
        // An expired code still says so once the Worker is back.
        _pollFailures++;
        if (_pollFailures >= _pollErrorThreshold && current()) {
          setState(() {
            _notice = tr('tv_phone_sign_in_service_unreachable');
            _pollError = true;
          });
        }
        continue;
      }
      if (!current()) return;
      if (_pollFailures > 0 || _pollError) {
        // The service is back: clear the outage error and the count.
        setState(() {
          _pollFailures = 0;
          _pollError = false;
          _notice = null;
        });
      }
      switch (check.status) {
        case TvQrSignInStatus.pending:
          continue;
        case TvQrSignInStatus.approved:
          return _finish(check);
        case TvQrSignInStatus.denied:
          return _newCode(notice: tr('tv_phone_sign_in_denied'));
        case TvQrSignInStatus.expired:
        case TvQrSignInStatus.consumed:
          // Expired, or spent: either way this code can never sign the
          // TV in, so a fresh one takes its place and nothing is left
          // half-signed-in.
          return _newCode(notice: tr('tv_phone_sign_in_expired'));
      }
    }
  }

  Future<void> _finish(TvQrSignInCheck check) async {
    if (!mounted) return;
    setState(() => _signingIn = true);
    context.read<SettingsProvider>().analytics.trackLogin('phone');
    await AuthNavigationService.returnToAppRoot(
      context,
      authenticatedUserId: check.signedInUid!,
    );
  }

  void _useRemote() {
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(builder: (_) => const TvAuthScreen.signIn()),
    );
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final palette = TvPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: TvDesign.surfaceFor(context),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.9, -1),
            radius: 1.4,
            colors: <Color>[
              accent.withValues(alpha: palette.dark ? 0.16 : 0.08),
              palette.page.withValues(alpha: 0),
            ],
          ),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 650;
              final qrSize = (constraints.maxHeight * 0.66).clamp(200.0, 380.0);
              // Scrolls on short screens: a denial or expiry notice adds
              // a line, and upstream's fixed row overflows there.
              return SingleChildScrollView(
                child: Row(
                  children: <Widget>[
                    Expanded(child: _instructions(context, compact)),
                    SizedBox(width: compact ? 32 : 56),
                    _qr(context, qrSize),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _instructions(BuildContext context, bool compact) {
    final palette = TvPalette.of(context);
    final code = _code;
    final body = TextStyle(
      color: palette.mutedText,
      fontSize: compact ? 15 : 18,
      height: 1.35,
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          tr('tv_phone_sign_in'),
          style: TextStyle(
            color: palette.foreground,
            fontFamily: 'FigtreeBold',
            fontSize: compact ? 28 : 36,
            letterSpacing: -0.45,
            height: 1.1,
          ),
        ),
        SizedBox(height: compact ? 16 : 24),
        for (final (index, key) in const <String>[
          'tv_phone_sign_in_step1',
          'tv_phone_sign_in_approve',
          'tv_phone_sign_in_step3',
        ].indexed)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 10 : 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: compact ? 26 : 30,
                  height: compact ? 26 : 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.idleFill,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: palette.foreground,
                      fontFamily: 'FigtreeSB',
                      fontSize: compact ? 13 : 15,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr(key),
                    style: TextStyle(
                      color: palette.foreground,
                      fontFamily: 'FigtreeSB',
                      fontSize: compact ? 16 : 19,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(height: compact ? 8 : 14),
        if (code != null) ...<Widget>[
          Text(
            tr('tv_phone_sign_in_enter_code'),
            style: body,
          ),
          const SizedBox(height: 4),
          Text(
            code.displayCode,
            style: TextStyle(
              color: palette.foreground,
              fontFamily: 'FigtreeBold',
              fontSize: compact ? 30 : 38,
              letterSpacing: 4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('tv_phone_sign_in_renews'),
            style: body.copyWith(fontSize: compact ? 13 : 15),
          ),
        ],
        if (_notice != null) ...<Widget>[
          SizedBox(height: compact ? 10 : 14),
          Text(
            _notice!,
            style: body.copyWith(
              color: palette.foreground,
              fontFamily: 'FigtreeSB',
            ),
          ),
        ],
        SizedBox(height: compact ? 18 : 26),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            TvPillButton(
              label: tr('tv_phone_sign_in_use_remote'),
              icon: PhosphorIcons.keyboard(),
              autofocus: true,
              enabled: !_signingIn,
              height: compact ? 46 : 52,
              onActivate: _useRemote,
            ),
            TvPillButton(
              label: tr('tv_phone_sign_in_new_code'),
              icon: PhosphorIcons.arrowsClockwise(),
              enabled: _service.isWorkerConfigured &&
                  !_signingIn &&
                  (_code != null || _problem != null),
              height: compact ? 46 : 52,
              onActivate: _newCode,
            ),
            if (_pollError && _code != null)
              TvPillButton(
                label: tr('retry'),
                icon: PhosphorIcons.arrowsClockwise(),
                enabled: !_signingIn,
                height: compact ? 46 : 52,
                onActivate: _retryPoll,
              ),
          ],
        ),
      ],
    );
  }

  Widget _qr(BuildContext context, double size) {
    final code = _code;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(TvDesign.cardRadius * 2),
      ),
      child: _signingIn
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox.square(
                  dimension: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tr('tv_phone_sign_in_signing_in'),
                  style: const TextStyle(
                    color: Colors.black87,
                    fontFamily: 'FigtreeSB',
                    fontSize: 17,
                  ),
                ),
              ],
            )
          : code != null
              ? Semantics(
                  label: tr('tv_phone_sign_in_step1'),
                  image: true,
                  child: QrImageView(
                    data: code.qrData,
                    size: size,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.all(20),
                  ),
                )
              : _problem != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _problem!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                          height: 1.35,
                        ),
                      ),
                    )
                  : const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black45,
                      ),
                    ),
    );
  }
}
