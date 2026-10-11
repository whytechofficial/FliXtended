import 'package:http/http.dart' as http;

import '../../models/vast_preroll_config.dart';
import 'vast.dart';

/// The pre-roll the player shows and the network that served it.
typedef VastPreroll = ({
  VastAd ad,
  VastMediaFile media,
  VastPrerollSource source,
});

/// Stub: ad serving is disabled in this build, so the client never loads.
class VastClient {
  VastClient({http.Client? httpClient, Future<String> Function()? userAgent});

  Future<VastAd?> load(
    Uri tag, {
    required Duration timeout,
    int maxWrappers = 5,
  }) async =>
      null;

  Future<VastPreroll?> loadPreroll(
    List<VastPrerollSource> sources, {
    required int maxHeight,
    int? maxBitrate,
    bool Function()? cancelled,
  }) async =>
      null;

  void send(
    Iterable<Uri> urls, {
    int? errorCode,
    Duration? adPlayhead,
    Uri? assetUri,
  }) {}

  void close() {}
}
