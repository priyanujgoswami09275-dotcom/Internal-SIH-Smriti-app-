from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest


NOW = datetime(2026, 9, 17, 16, 0, tzinfo=timezone.utc)


def session(identifier, days=1, **changes):
    completed = NOW - timedelta(days=days)
    values = dict(
        id=identifier, patient_id="p", game_type="match_it", difficulty_level=1,
        started_at=completed - timedelta(seconds=60), completed_at=completed,
        accuracy_pct=90.0, avg_response_time_ms=1000.0, raw_event_log=[],
        origin="real",
    )
    values.update(changes)
    return SimpleNamespace(**values)


def test_strict_last_three_isolated_and_future_events_excluded():
    from app.services.adaptive_features import extract_features

    rows = [session("old", 4, accuracy_pct=0), session("a", 3, accuracy_pct=80),
            session("b", 2), session("c", 1, accuracy_pct=100),
            session("future", -1), session("equal", 0),
            session("other-patient", patient_id="q"),
            session("other-game", game_type="number_recall"),
            session("synthetic", origin="synthetic"), session("incomplete", completed_at=None)]
    rows[3].raw_event_log = [
        dict(action_type="flip_card", is_correct=False, timestamp=(NOW + timedelta(seconds=1)).isoformat()),
        dict(action_type="flip_card", is_correct=True, timestamp=rows[3].completed_at.isoformat()),
    ]
    result = extract_features(rows, "p", "match_it", 1, NOW)
    assert result.reason == "eligible"
    assert result.session_ids == ("c", "b", "a")
    assert result.values[0] == 90.0
    assert result.values[2] == 0.0
    assert result.missing == (False, False, False, True, True, False)


@pytest.mark.parametrize("count", [0, 1, 2])
def test_fewer_than_three_skips_shadow(count):
    from app.services.adaptive_features import extract_features

    result = extract_features([session(str(i), i + 1) for i in range(count)], "p", "match_it", 1, NOW)
    assert result.values is None
    assert result.reason == "insufficient_history"


def test_absent_telemetry_is_missing_not_zero():
    from app.services.adaptive_features import extract_features

    rows = [session(str(i), i + 1, avg_response_time_ms=0) for i in range(3)]
    result = extract_features(rows, "p", "match_it", 1, NOW)
    assert result.values == (90.0, None, None, None, None, 1.0)
    assert result.missing == (False, True, True, True, True, False)


def test_missing_accuracy_does_not_backfill_an_older_session():
    from app.services.adaptive_features import extract_features

    rows = [session(str(i), i + 1) for i in range(4)]
    rows[0].accuracy_pct = None
    assert extract_features(rows, "p", "match_it", 1, NOW).reason == "missing_accuracy"


@pytest.mark.parametrize("game,action,index", [
    ("match_it", "flip_card", 2), ("routine_sequencing", "place_step", 3),
    ("number_recall", "recall_tap", 4),
])
def test_categories_count_only_resolved_matching_actions(game, action, index):
    from app.services.adaptive_features import extract_features

    rows = [session(str(i), i + 1, game_type=game) for i in range(3)]
    for row in rows:
        row.raw_event_log = [dict(action_type=kind, is_correct=correct,
                                 timestamp=row.completed_at.isoformat())
                             for kind, correct in [(action, True), (action, False),
                                                   (action, None), ("stuck", False)]]
    result = extract_features(rows, "p", game, 2, NOW)
    assert result.values[index] == 0.5
    assert all(result.values[i] is None for i in (2, 3, 4) if i != index)


def test_timestamp_ties_are_ordered_by_id_and_invalid_start_is_refused():
    from app.services.adaptive_features import extract_features

    rows = [session(key) for key in ("a", "d", "c", "b")]
    assert extract_features(rows, "p", "match_it", 1, NOW).session_ids == ("d", "c", "b")
    rows[1].started_at = NOW
    assert extract_features(rows, "p", "match_it", 1, NOW).reason == "invalid_timestamp"


def test_naive_utc_session_timestamps_are_treated_as_utc():
    """DateTime columns store naive UTC; must not be shifted by server local TZ."""
    from app.services.adaptive_features import extract_features

    rows = []
    for i in range(3):
        completed = (NOW - timedelta(days=i + 1)).replace(tzinfo=None)
        rows.append(session(str(i), completed_at=completed,
                             started_at=(completed - timedelta(seconds=60))))
    result = extract_features(rows, "p", "match_it", 1, NOW)
    assert result.reason == "eligible"
    assert result.values is not None


def test_no_sensitive_attributes_are_read():
    from app.services.adaptive_features import extract_features

    class Restricted(SimpleNamespace):
        def __getattribute__(self, name):
            if name in ("risk_score", "clinical_features", "patient", "risk_screenings"):
                raise AssertionError("Forbidden attribute")
            return super().__getattribute__(name)

    rows = [Restricted(**vars(session(str(i), i + 1))) for i in range(3)]
    assert extract_features(rows, "p", "match_it", 1, NOW).reason == "eligible"
