import 'package:flutter/material.dart';

import '../models/adsterra_playback_ads_config.dart';
import '../services/playback_ad_input_service.dart';

typedef StoreLauncher = Future<bool> Function(Uri uri);

/// Stub: ad preloading is disabled in this build.
class PlaybackAdPreload {
  PlaybackAdPreload({required this.placement, VoidCallback? onReleased});

  final PlaybackAdPlacement placement;
  Future<Object?> get ready async => null;
  bool get unavailable => true;
  void claim() {}
  void dispose() {}
}

/// Stub: ad playback screens are disabled in this build; renders nothing.
class AdsterraPlaybackAdScreen extends StatelessWidget {
  const AdsterraPlaybackAdScreen(
      {required this.placement,
      required this.stage,
      this.storeLauncher,
      this.holdClose = true,
      this.television = false,
      this.preload,
      this.continueTap,
      this.onAdShown,
      super.key});
  final PlaybackAdPlacement placement;
  final PlaybackAdStage stage;
  final StoreLauncher? storeLauncher;
  final PlaybackAdPreload? preload;
  final PlaybackContinueTap? continueTap;

  /// Called once when advertiser content first becomes visible. This is a
  /// local presentation signal, not a network-confirmed paid impression.
  final VoidCallback? onAdShown;

  /// Whether the ad page hides its close control until the ad is served.
  /// False for a page the viewer opened themselves, such as a video ad's
  /// "Visit advertiser".
  final bool holdClose;

  /// Android TV: larger type, overscan margins and D-pad focus.
  final bool television;

  /// How long the final ad stays up before the viewer moves on, counted from
  /// when it first shows content, so the advertiser gets a real view.
  static const minimumView = Duration(seconds: 3);

  /// How long one content check may run. A check sent while the document is
  /// being replaced may never answer.
  static const contentCheckTimeout = Duration(seconds: 2);

  /// How long a page with visible content must go without another navigation
  /// before it counts as the final redirect.
  static const redirectSettle = Duration(milliseconds: 800);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
