import argparse
from datetime import datetime, timezone
import json
import logging
import os
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID

from sqlalchemy import create_engine, select

from app.models.all_models import DifficultyAdjustmentLog, GameLevelConfig, GameSession
from app.models.compliance import ConsentRecord
from app.services.adaptive_features import timestamp
from app.services.adaptive_training import build_examples, synthetic_examples, train_candidate


MODEL_ROOT = Path(__file__).resolve().parent / "ml_models" / "adaptive_success"


def extract_real(connection, patient_ids, since, until):
    since, until = timestamp(since), timestamp(until)
    if since is None or until is None or since >= until:
        raise ValueError("invalid_extraction_window")
    consent = ConsentRecord.__table__
    consent_rows = connection.execute(select(consent.c.patient_id, consent.c.granted_at).where(
        consent.c.patient_id.in_(patient_ids), consent.c.scope.in_(("all", "game_data")),
        consent.c.revoked_at.is_(None), consent.c.granted_at <= since,
    )).all()
    allowed = {row.patient_id for row in consent_rows}
    exclusions = {"patients_without_active_game_consent": len(set(patient_ids) - allowed)}
    if not allowed:
        return [], exclusions
    session = GameSession.__table__
    sessions = connection.execute(select(
        session.c.id, session.c.patient_id, session.c.game_type, session.c.difficulty_level,
        session.c.started_at, session.c.completed_at, session.c.accuracy_pct,
        session.c.avg_response_time_ms, session.c.raw_event_log,
    ).where(session.c.patient_id.in_(allowed), session.c.completed_at >= since,
            session.c.completed_at <= until)).mappings().all()
    log = DifficultyAdjustmentLog.__table__
    decisions = connection.execute(select(
        log.c.id, log.c.patient_id, log.c.game_type, log.c.old_difficulty, log.c.adjusted_at,
    ).where(log.c.patient_id.in_(allowed), log.c.adjusted_at >= since, log.c.adjusted_at < until)).mappings().all()
    config = GameLevelConfig.__table__
    configs = connection.execute(select(config.c.game_type, config.c.level, config.c.params)).all()
    examples, counts, label_targets = build_examples(
        [SimpleNamespace(**row) for row in decisions], [SimpleNamespace(**row) for row in sessions],
        {(row.game_type, row.level): row.params for row in configs if isinstance(row.params, dict)}, until,
    )
    return examples, {**exclusions, **counts}, label_targets


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", required=True, choices=("synthetic", "real"))
    parser.add_argument("--seed", type=int, choices=(42,), default=42)
    parser.add_argument("--output", required=True)
    parser.add_argument("--authorize-real-extraction", action="store_true")
    parser.add_argument("--patient-ids-file")
    parser.add_argument("--since")
    parser.add_argument("--until")
    args = parser.parse_args(argv)
    report = None
    if args.mode == "real" and not (args.authorize_real_extraction and args.patient_ids_file and args.since and args.until):
        report = dict(status="authorization_required", reason="Explicit real-only patient allowlist, game-data consent, and extraction bounds required")
    output = Path(args.output)
    if report is None and (output.suffix != ".joblib" or not output.resolve().is_relative_to(MODEL_ROOT.resolve()) or not output.parent.is_dir()):
        report = dict(status="invalid_output", reason="Use an existing directory under backend/ml_models/adaptive_success")
    if report is None:
        try:
            if args.mode == "synthetic":
                examples, exclusions, label_targets = synthetic_examples(args.seed)
            else:
                database_url = os.environ.get("ADAPTIVE_TRAIN_DATABASE_URL")
                if not database_url:
                    raise ValueError("explicit_database_required")
                since, until = timestamp(args.since), timestamp(args.until)
                if since is None or until is None or since >= until or until > datetime.now(timezone.utc):
                    raise ValueError("invalid_extraction_window")
                identifiers = json.loads(Path(args.patient_ids_file).read_text())
                if not isinstance(identifiers, list) or not identifiers:
                    raise ValueError("invalid_patient_allowlist")
                patient_ids = [UUID(value) for value in identifiers]
                logging.getLogger("sqlalchemy.engine").disabled = True
                engine = create_engine(database_url, echo=False, hide_parameters=True)
                try:
                    with engine.connect() as connection:
                        if connection.dialect.name == "postgresql":
                            connection.exec_driver_sql("SET TRANSACTION READ ONLY")
                        elif connection.dialect.name == "sqlite":
                            connection.exec_driver_sql("PRAGMA query_only=ON")
                        else:
                            raise ValueError("unsupported_database")
                        examples, exclusions, label_targets = extract_real(connection, patient_ids, since, until)
                finally:
                    engine.dispose()
            report = train_candidate(examples, output, origin=args.mode, exclusions=exclusions, seed=args.seed,
                                     label_targets=label_targets)
        except Exception:
            report = dict(status="training_refused", reason="Invalid extraction settings, unavailable data, or training/write failure; no candidate replaced")
    print(json.dumps(report, sort_keys=True))
    return 0 if report["status"] == "fitted" else 2


if __name__ == "__main__":
    raise SystemExit(main())
