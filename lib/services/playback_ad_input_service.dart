/// Stub: ad input is disabled in this build.
typedef PlaybackContinueTap = Future<bool> Function(
    Object controller, Uri document);

/// Stub: always reports that the tap was not performed.
Future<bool> tapPlaybackContinue(
    Object controller, Uri document) async {
  return false;
}
