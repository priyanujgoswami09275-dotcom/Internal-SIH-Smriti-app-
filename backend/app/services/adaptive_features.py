from dataclasses import dataclass
from datetime import datetime, timezone
from math import isfinite
from statistics import mean


SCHEMA_VERSION = "adaptive-last3-v1"
FEATURE_NAMES = ("mean_accuracy", "mean_response_time_ms", "mismatch", "sequence_position", "recall_position", "current_level")
INPUT_NAMES = FEATURE_NAMES + tuple(f"{name}_missing" for name in FEATURE_NAMES)
ACTIONS = {"match_it": ("flip_card", 2), "routine_sequencing": ("place_step", 3), "number_recall": ("recall_tap", 4)}


@dataclass(frozen=True)
class Features:
    values: tuple | None
    missing: tuple = ()
    session_ids: tuple = ()
    reason: str = "eligible"

    def model_row(self):
        if self.values is None:
            raise ValueError(self.reason)
        return [float("nan") if value is None else value for value in self.values] + list(map(float, self.missing))


def timestamp(value):
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    if not isinstance(value, datetime):
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def number(value, minimum=0, maximum=float("inf")):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if isfinite(value) and minimum <= value <= maximum else None


def game_name(value):
    return getattr(value, "value", value)


def session_origin(session):
    origin = getattr(session, "origin", None)
    events = getattr(session, "raw_event_log", None)
    markers = [origin] if origin is not None else []
    if isinstance(events, dict):
        markers.append(events.get("origin"))
    elif isinstance(events, list):
        markers.extend(event.get("origin") for event in events if isinstance(event, dict) and "origin" in event)
    if any(marker not in (None, "real") for marker in markers):
        return "synthetic" if all(marker in (None, "real", "synthetic") for marker in markers) else "unknown"
    return "real"


def extract_features(sessions, patient_id, game_type, current_level, decision_time, *, origin="real"):
    decision = timestamp(decision_time)
    game = game_name(game_type)
    if decision is None:
        return Features(None, reason="invalid_timestamp")
    if current_level not in (1, 2, 3) or game not in ACTIONS:
        return Features(None, reason="invalid_context")
    if current_level == 3:
        return Features(None, reason="top_level")
    candidates = []
    for session in sessions:
        if str(session.patient_id) != str(patient_id) or game_name(session.game_type) != game or session_origin(session) != origin:
            continue
        if session.completed_at is None:
            continue
        completed = timestamp(session.completed_at)
        if completed is None:
            return Features(None, reason="invalid_timestamp")
        if completed < decision:
            candidates.append((completed, str(session.id), session))
    candidates.sort(key=lambda row: row[:2], reverse=True)
    if len(candidates) < 3:
        return Features(None, reason="insufficient_history")
    selected = candidates[:3]
    accuracies, times, errors = [], [], []
    for completed, identifier, session in selected:
        started = timestamp(session.started_at)
        if started is None or started > completed:
            return Features(None, reason="invalid_timestamp")
        accuracy = number(session.accuracy_pct, maximum=100)
        if accuracy is None:
            return Features(None, reason="missing_accuracy")
        accuracies.append(accuracy)
        events = session.raw_event_log if isinstance(session.raw_event_log, list) else []
        valid_events = []
        for event in events:
            if not isinstance(event, dict):
                continue
            when = timestamp(event.get("timestamp"))
            if when is not None and started <= when <= completed and when < decision:
                valid_events.append(event)
        action, index = ACTIONS[game]
        for event in valid_events:
            if event.get("action_type") == action and isinstance(event.get("is_correct"), bool):
                errors.append(not event["is_correct"])
        response = number(session.avg_response_time_ms)
        if response is not None and response > 0:
            times.append(response)
    values = [mean(accuracies), mean(times) if times else None, None, None, None, float(current_level)]
    values[index] = mean(errors) if errors else None
    return Features(tuple(values), tuple(value is None for value in values), tuple(row[1] for row in selected))
