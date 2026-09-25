/// Shadow-only next-level success display helpers (Phase B-01).
///
/// The backend attaches nullable `shadow_*` fields to the session-complete
/// response. Rules remain the sole difficulty authority — this label is
/// experimental observability only and must never be framed as a decision.
library;

import '../models/game_models.dart';

/// Humanized reason when the model did not produce a probability.
String shadowReasonLabel(String reason) {
  switch (reason) {
    case 'disabled':
      return 'disabled';
    case 'unsupported_game':
      return 'not supported for this game';
    case 'top_level':
      return 'at top difficulty';
    case 'artifact_missing':
    case 'artifact_invalid':
    case 'artifact_incompatible':
    case 'unsafe_artifact_path':
    case 'inference_error':
    case 'invalid_probability':
      return 'unavailable';
    default:
      return reason;
  }
}

/// One-line experimental shadow label for a completion dialog, or null when
/// the summary carries no shadow fields (offline / older payloads).
String? shadowModelLabel(GameSessionSummary? summary) {
  if (summary == null) return null;
  final p = summary.shadowProbability;
  if (p != null) {
    final pct = (p * 100).toStringAsFixed(0);
    return 'Shadow model (experimental): $pct% next-level success';
  }
  final reason = summary.shadowReason;
  if (reason != null && reason != 'predicted') {
    return 'Shadow model: ${shadowReasonLabel(reason)}';
  }
  return null;
}
