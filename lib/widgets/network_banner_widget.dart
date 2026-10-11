import 'package:flutter/material.dart';

import '../models/banner_ads_config.dart';

/// Stub: ad banners are disabled in this build, so this renders nothing.
class NetworkBannerWidget extends StatelessWidget {
  static const documentBaseUrl =
      'https://appassets.androidplatform.net/adsterra/';

  static bool get isSupported => false;

  const NetworkBannerWidget({
    required this.placement,
    required this.unit,
    this.television = false,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 6),
    super.key,
  });

  final String placement;
  final BannerAdUnit unit;
  final bool television;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
