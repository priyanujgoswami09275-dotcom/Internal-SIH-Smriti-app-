from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from hashlib import sha256
from pathlib import Path
from types import SimpleNamespace
import os
import tempfile

from app.services.adaptive_features import (
    Features, INPUT_NAMES, SCHEMA_VERSION, extract_features, game_name, number,
    session_origin, timestamp,
)
from app.services.level_config_service import default_params


EVIDENCE = "synthetic bootstrap — assumption conformity; not patient performance or clinical evidence"
BIAS = "Only played, completed, evaluable next-higher-level outcomes are labeled; observed-outcome selection bias applies."
LABEL_TARGETS_NOTE = ("target_seconds resolved from DB level-config rows when present, else current code defaults "
                      "at training time; later config changes can retroactively alter real-data labels.")


@dataclass(frozen=True)
class Example:
    patient_id: str
    features: Features
    label: int
    origin: str


def build_examples(decisions, sessions, level_params, as_of, *, origin="real"):
    grouped = defaultdict(list)
    for session in sessions:
        if session_origin(session) == origin:
            grouped[(str(session.patient_id), game_name(session.game_type))].append(session)
    examples, excluded, label_targets = [], Counter(), {}
    cutoff = timestamp(as_of)
    if cutoff is None:
        raise ValueError("invalid_extraction_time")
    for decision in sorted(decisions, key=lambda d: (str(d.patient_id), str(d.adjusted_at), str(d.id))):
        when = timestamp(decision.adjusted_at)
        if when is None or when > cutoff:
            excluded["invalid_decision_timestamp"] += 1
            continue
        game = game_name(decision.game_type)
        rows = grouped[(str(decision.patient_id), game)]
        features = extract_features(rows, decision.patient_id, game, decision.old_difficulty, when, origin=origin)
        if features.values is None:
            excluded[features.reason] += 1
            continue
        candidates = []
        invalid_outcome = False
        for row in rows:
            if row.difficulty_level != decision.old_difficulty + 1 or row.completed_at is None:
                continue
            completed = timestamp(row.completed_at)
            if completed is None:
                invalid_outcome = True
                continue
            if when < completed <= min(when + timedelta(days=30), cutoff):
                candidates.append((completed, str(row.id), row))
        if invalid_outcome:
            excluded["invalid_outcome_timestamp"] += 1
            continue
        if not candidates:
            excluded["missing_outcome"] += 1
            continue
        completed, _, target = min(candidates, key=lambda row: row[:2])
        started = timestamp(target.started_at)
        if started is None or started > completed:
            excluded["invalid_outcome_timestamp"] += 1
            continue
        if started < when:
            excluded["outcome_started_before_decision"] += 1
            continue
        accuracy = number(target.accuracy_pct, maximum=100)
        if accuracy is None:
            excluded["missing_outcome_accuracy"] += 1
            continue
        params = default_params(game, target.difficulty_level)
        params.update(level_params.get((game, target.difficulty_level), {}))
        seconds = number(params.get("target_seconds"))
        if seconds is None or seconds <= 0:
            excluded["missing_target"] += 1
            continue
        label = int(accuracy >= 85 and (completed - started).total_seconds() <= seconds)
        label_targets.setdefault(f"{game}:{target.difficulty_level}", seconds)
        examples.append(Example(str(decision.patient_id), features, label, origin))
    return examples, dict(excluded), label_targets


def synthetic_examples(seed=42):
    import numpy as np

    if seed != 42:
        raise ValueError("seed_must_be_42")
    rng = np.random.default_rng(seed)
    examples = []
    games = (("match_it", "flip_card"), ("routine_sequencing", "place_step"), ("number_recall", "recall_tap"))
    # Assumptions only: higher accuracy and faster responses support next-level
    # success; category-local weakness and higher level reduce it independently.
    # Aggregate accuracy and localized errors vary independently to model a weak
    # subtask despite a good aggregate; these are not empirical patient claims.
    # Outcomes are Bernoulli draws, not difficulty-rule labels. Missing telemetry
    # is random (10%); one game supplies only its honest action category.
    for patient in range(100):
        for transition in range(12):
            game, action = games[transition % 3]
            level = int(rng.integers(1, 3))
            accuracy = float(rng.uniform(55, 100))
            response = float(rng.uniform(700, 6500))
            weakness = float(rng.uniform(0, 0.7))
            when = datetime(2025, 1, 10, tzinfo=timezone.utc) + timedelta(days=transition * 40)
            rows = []
            for index in range(3):
                completed = when - timedelta(days=index + 1)
                errors = int(round(weakness * 20))
                events = [dict(action_type=action, action_data={"position": i}, is_correct=i >= errors,
                               timestamp=(completed - timedelta(seconds=20 - i)).isoformat(), origin="synthetic")
                          for i in range(20)]
                if rng.random() < 0.1:
                    events = [{"origin": "synthetic"}]
                rows.append(SimpleNamespace(
                    id=f"synthetic-{patient}-{transition}-{index}", patient_id=f"synthetic-{patient:03}",
                    game_type=game, difficulty_level=level, started_at=completed - timedelta(seconds=60),
                    completed_at=completed, accuracy_pct=float(np.clip(accuracy + rng.normal(0, 2), 0, 100)),
                    avg_response_time_ms=response if rng.random() >= 0.1 else None,
                    raw_event_log=events, origin="synthetic",
                ))
            features = extract_features(rows, rows[0].patient_id, game, level, when, origin="synthetic")
            logit = 0.8 + 0.09 * (accuracy - 80) - 0.00045 * (response - 2500) - 5 * weakness - 0.5 * (level - 1)
            success = rng.random() < 1 / (1 + np.exp(-logit))
            # The assumed next-level completion is evaluable under the same label
            # definition: >=85% and within configured target, otherwise failure.
            target_seconds = default_params(game, level + 1)["target_seconds"]
            outcome_accuracy = 90 if success else 70
            outcome_duration = target_seconds * (0.8 if success else 1.2)
            label = int(outcome_accuracy >= 85 and outcome_duration <= target_seconds)
            examples.append(Example(rows[0].patient_id, features, label, "synthetic"))
    return examples, {}, _synthetic_targets()


def _synthetic_targets():
    return {f"{game}:{level + 1}": default_params(game, level + 1)["target_seconds"]
            for game in ("match_it", "routine_sequencing", "number_recall") for level in (1, 2)}


def train_candidate(examples, output, *, origin, exclusions=None, seed=42, label_targets=None):
    import joblib
    import numpy as np
    import sklearn
    from sklearn.impute import SimpleImputer
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import accuracy_score, roc_auc_score
    from sklearn.model_selection import GroupShuffleSplit
    from sklearn.pipeline import Pipeline
    from sklearn.preprocessing import StandardScaler

    if seed != 42 or origin not in ("real", "synthetic"):
        raise ValueError("invalid_training_settings")
    examples = [example for example in examples if example.origin == origin]
    labels = np.array([e.label for e in examples], dtype=int)
    groups = np.array([e.patient_id for e in examples])
    counts = lambda indices: {str(label): int(sum(labels[indices] == label)) for label in (0, 1)}
    overall = counts(np.arange(len(examples)))
    report = dict(status="insufficient_data", rows=len(examples), patients=len(set(groups)),
                  class_counts={"overall": overall}, exclusions=exclusions or {},
                  label_targets=dict(label_targets or {}), label_targets_note=LABEL_TARGETS_NOTE,
                  evidence=EVIDENCE if origin == "synthetic" else "Observed outcomes; demo candidate, not clinical evidence",
                  selection_bias=BIAS)
    if origin == "real" and (len(examples) < 100 or len(set(groups)) < 10 or min(overall.values()) < 10):
        return {**report, "reason": "requires_100_transitions_10_patients_10_per_class"}
    if len(set(groups)) < 2 or min(overall.values()) == 0:
        return {**report, "reason": "requires_two_groups_and_both_training_classes"}
    rows = np.array([e.features.model_row() for e in examples], dtype=float)
    train, test = next(GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42).split(rows, labels, groups))
    train_groups, test_groups = set(groups[train]), set(groups[test])
    identity = sha256(("train:" + "|".join(sorted(train_groups)) + ";test:" + "|".join(sorted(test_groups))).encode()).hexdigest()
    split = dict(method="GroupShuffleSplit", n_splits=1, test_size=0.2, seed=42,
                 train_rows=len(train), test_rows=len(test), train_groups=len(train_groups), test_groups=len(test_groups),
                 disjoint=train_groups.isdisjoint(test_groups), identity=identity)
    report["split"] = split
    report["class_counts"].update(train=counts(train), test=counts(test))
    if min(counts(train).values()) == 0 or (origin == "real" and min(counts(test).values()) == 0):
        return {**report, "reason": "both_classes_required_in_train_and_test"}
    output = Path(output)
    if output.exists() or output.is_symlink():
        return {**report, "status": "output_exists"}
    pipeline = Pipeline([
        ("imputer", SimpleImputer(strategy="median", keep_empty_features=True)),
        ("scaler", StandardScaler()),
        ("classifier", LogisticRegression(random_state=42, max_iter=1000)),
    ])
    pipeline.fit(rows[train], labels[train])
    probability = pipeline.predict_proba(rows[test])[:, 1]
    metrics = dict(accuracy=float(accuracy_score(labels[test], pipeline.predict(rows[test]))),
                   roc_auc=float(roc_auc_score(labels[test], probability)) if min(counts(test).values()) else None)
    version = f"adaptive-{origin}-v1-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}"
    artifact = dict(format_version=1, schema_version=SCHEMA_VERSION, input_names=INPUT_NAMES, seed=42,
                    origin=origin, version=version, sklearn_version=sklearn.__version__, pipeline=pipeline,
                    split=split, metrics=metrics, class_counts=report["class_counts"], evidence=report["evidence"],
                    exclusions=report["exclusions"], selection_bias=BIAS,
                    label_targets=report["label_targets"], label_targets_note=LABEL_TARGETS_NOTE)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix=".adaptive-", delete=False) as handle:
            temporary = Path(handle.name)
            joblib.dump(artifact, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.link(temporary, output)
    except FileExistsError:
        return {**report, "status": "output_exists"}
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return {**report, "status": "fitted", "version": version, "metrics": metrics}
