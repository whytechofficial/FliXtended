// Pure rules for offline-download playback resume. The offline player
// persists its position per download id (see `SettingsPreferences`);
// these helpers decide when that saved position should be discarded
// instead of restored.

/// Mirrors the streaming rule in `player_data_management.dart`: a title
/// watched past 85% counts as finished, so its resume point is discarded
/// instead of restored. An unknown duration can never clear a position.
bool shouldClearOfflineResume({
  required int positionMs,
  required int durationMs,
}) {
  if (durationMs <= 0 || positionMs <= 0) return false;
  return positionMs / durationMs > 0.85;
}
