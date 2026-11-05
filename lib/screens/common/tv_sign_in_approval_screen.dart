import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../design/app_palette.dart';
import '../../design/app_tokens.dart';
import '../../mobile/widgets/page_kit.dart';
import '../../mobile/widgets/pill_button.dart';
import '../../ui_components/app_ui_components.dart';
import '../../services/tv_qr_sign_in_service.dart';

/// The phone side of TV QR sign-in: the viewer types the short code the
/// TV shows, and approves or declines it. Approval binds the TV's code
/// to this phone's account; the TV then signs in as that account.
///
/// Reached from My FliXtended under "Sign in a TV". Only a signed-in
/// phone user can approve — a guest sees that plainly instead of a
/// code box that could never work.
class TvSignInApprovalScreen extends StatefulWidget {
  const TvSignInApprovalScreen({this.service, super.key});

  /// Stands in for Firestore in tests.
  final TvQrSignInService? service;

  @override
  State<TvSignInApprovalScreen> createState() =>
      _TvSignInApprovalScreenState();
}

class _TvSignInApprovalScreenState extends State<TvSignInApprovalScreen> {
  late final TvQrSignInService _service =
      widget.service ?? FirebaseTvQrSignInService();
  final _codeController = TextEditingController();
  TvQrApprovalRequest? _found;
  String? _message;
  bool _busy = false;

  bool get _signedIn => _service.currentUid != null;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Formats typed codes as XXXX-XXXX while typing.
  static String _formatCode(String input) {
    final clean =
        input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final clipped = clean.length > 8 ? clean.substring(0, 8) : clean;
    if (clipped.length <= 4) return clipped;
    return '${clipped.substring(0, 4)}-${clipped.substring(4)}';
  }

  String _errorMessage(TvQrSignInException error) {
    switch (error.code) {
      case 'not-found':
        return tr('tv_sign_in_code_not_found');
      case 'expired':
        return tr('tv_sign_in_code_expired');
      case 'already-resolved':
        return tr('tv_sign_in_code_expired');
      case 'signed-out':
        return tr('tv_sign_in_sign_in_required');
      default:
        return error.message;
    }
  }

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _message = null;
      _found = null;
    });
    try {
      final found = await _service.findPendingCode(_codeController.text);
      if (!mounted) return;
      setState(() => _found = found);
    } on TvQrSignInException catch (error) {
      if (!mounted) return;
      setState(() => _message = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(bool approve) async {
    final found = _found;
    if (found == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (approve) {
        await _service.approveCode(found.codeId);
      } else {
        await _service.denyCode(found.codeId);
      }
      if (!mounted) return;
      setState(() {
        _message = approve
            ? tr('tv_sign_in_approved')
            : tr('tv_sign_in_declined');
        _found = null;
        _codeController.clear();
      });
    } on TvQrSignInException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _errorMessage(error);
        _found = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: PageAppBar(title: tr('tv_sign_in_approve_title')),
      body: AppResponsiveContent(
        padding: EdgeInsets.zero,
        maxWidth: 760,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter(context),
            AppSpace.sm,
            AppSpace.gutter(context),
            AppSpace.xxxl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const SizedBox(height: 12),
            if (!_signedIn)
              Text(
                tr('tv_sign_in_sign_in_required'),
                style: AppType.body.copyWith(color: palette.mutedText),
              )
            else ...[
              TextField(
                controller: _codeController,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: <TextInputFormatter>[
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final formatted = _formatCode(newValue.text);
                    return TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }),
                ],
                decoration: InputDecoration(
                  labelText: tr('tv_sign_in_enter_code_label'),
                  hintText: tr('tv_sign_in_enter_code_hint'),
                  prefixIcon: Icon(PhosphorIcons.qrCode()),
                ),
                onSubmitted: (_) => _find(),
              ),
              const SizedBox(height: 12),
              PillButton(
                label: tr('tv_sign_in_find_tv'),
                icon: PhosphorIcons.magnifyingGlass(),
                onPressed: _busy ? null : _find,
              ),
              if (_found != null) ...[
                const SizedBox(height: 24),
                Text(
                  tr('tv_sign_in_approval_prompt'),
                  style: AppType.body.copyWith(color: palette.foreground),
                ),
                const SizedBox(height: 4),
                Text(
                  _found!.displayCode,
                  style: AppType.body.copyWith(
                    color: palette.foreground,
                    fontFamily: 'FigtreeBold',
                    fontSize: 26,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: tr('tv_sign_in_approve'),
                        icon: PhosphorIcons.check(),
                        onPressed: _busy ? null : () => _decide(true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PillButton(
                        label: tr('tv_sign_in_deny'),
                        icon: PhosphorIcons.x(),
                        onPressed: _busy ? null : () => _decide(false),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(
                _message!,
                style: AppType.body.copyWith(color: palette.mutedText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
