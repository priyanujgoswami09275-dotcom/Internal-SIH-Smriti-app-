"""Game API Routes — Match It, Routine Sequencing, Number Recall, Odd-One-Out,
Adaptive Difficulty.

Endpoints:
   POST /games/sessions — start a new game
   POST /games/sessions/{session_id}/actions — record an action
   POST /games/sessions/{session_id}/complete — finish and compute metrics
   GET /games/sessions/{session_id} — retrieve session summary
   GET /patients/{patient_id}/games/history — trend data for dashboard
   GET /games/content-packs — list available content packs
   GET /games/content-packs/{pack_id}/board — generate Match It board
   POST /patients/{patient_id}/routine — set custom daily routine
   GET /patients/{patient_id}/routine — get patient's routine
   GET /routine/board — generate sequencing puzzle
   GET /games/odd-one-out/board — generate Odd-One-Out board (server-held answer)
"""
from typing import Optional
from datetime import datetime, timedelta, timezone
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel, Field

from sqlalchemy import select
from app.core.security import require_role
from app.deps import (
    get_current_user,
    ensure_consent,
    ensure_clinical_access,
    ensure_patient_access,
)
from app.db import get_db
from app.models.all_models import GameTypeEnum, PatientProfile, GameSession
from app.models.user import User
from app.services import game_service, difficulty_engine, routine_service, content_packs
from app.services import level_config_service, recall_service, odd_one_out_service
from app.services.datetime_utils import iso_utc
from app.services.dashboard_service import (
    GAME_METRIC_SCOPE,
    build_daily_trends,
    get_game_analytics,
)

router = APIRouter(prefix="/games", tags=["games"])


# ============= Role dependencies =============
require_patient = require_role("patient")
require_caregiver = require_role("family_caregiver", "asha_worker")
require_staff = require_role("family_caregiver", "asha_worker", "clinician")
require_viewer = require_role("patient", "family_caregiver", "asha_worker", "clinician")
require_admin = require_role("admin")


def _parse_pid(patient_id: str) -> UUID:
    """Malformed patient_id is a client error (422), never a 500."""
    try:
        return UUID(patient_id)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid patient_id '{patient_id}': must be a valid UUID",
        )


async def _ensure_owned_session(
    db: AsyncSession, current_user: User, session_id: UUID
) -> GameSession:
    """No-implicit-access for game sessions: a patient may only record actions
    on / complete a session bound to their OWN patient profile. Prevents a
    logged-in patient from mutating another patient's session by guessing its id.
    """
    res = await db.execute(select(GameSession).where(GameSession.id == session_id))
    session = res.scalar_one_or_none()
    if session is None:
        raise HTTPException(status_code=404, detail="Game session not found")
    pres = await db.execute(
        select(PatientProfile).where(PatientProfile.user_id == current_user.id)
    )
    patient = pres.scalar_one_or_none()
    if patient is None or session.patient_id != patient.id:
        raise HTTPException(
            status_code=403, detail="Game session does not belong to this account"
        )
    return session


async def _ensure_board_session(
    db: AsyncSession,
    current_user: User,
    session_id: Optional[UUID],
    game_type: GameTypeEnum,
    difficulty_level: int,
    *,
    patient_id: Optional[UUID] = None,
    content_pack_id: Optional[str] = None,
) -> Optional[GameSession]:
    if session_id is None:
        return None
    session = await _ensure_owned_session(db, current_user, session_id)
    if session.completed_at is not None:
        raise HTTPException(status_code=409, detail="Game session is already completed")
    if session.game_type != game_type:
        raise HTTPException(status_code=422, detail="session game_type does not match board")
    if session.difficulty_level != difficulty_level:
        raise HTTPException(status_code=422, detail="difficulty_level does not match session")
    if patient_id is not None and session.patient_id != patient_id:
        raise HTTPException(status_code=422, detail="patient_id does not match session")
    if (
        content_pack_id is not None
        and session.content_pack_id is not None
        and session.content_pack_id != content_pack_id
    ):
        raise HTTPException(status_code=422, detail="pack_id does not match session")
    return session


# ============= Schemas =============


class StartGameRequest(BaseModel):
    """Start a new game session."""
    game_type: str  # "match_it" | "routine_sequencing" | "number_recall" | "odd_one_out"
    difficulty_level: int = 1
    content_pack_id: Optional[str] = None  # For Match It
    routine_id: Optional[str] = None  # For Routine Sequencing
    idempotency_key: Optional[str] = Field(default=None, min_length=1, max_length=200)
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None


class RecordActionRequest(BaseModel):
    """Record a single player action."""
    action_type: str = Field(min_length=1, max_length=100)
    action_data: dict
    is_correct: Optional[bool] = None
    response_time_ms: Optional[int] = Field(default=None, ge=0)
    idempotency_key: Optional[str] = Field(default=None, min_length=1, max_length=200)


class CompleteGameRequest(BaseModel):
    idempotency_key: Optional[str] = Field(default=None, min_length=1, max_length=200)
    expected_action_ids: list[str] = Field(default_factory=list, max_length=1000)
    completed_at: Optional[datetime] = None


class SessionSummaryResponse(BaseModel):
    """Completed game session summary.

    recommended_level / difficulty_* / rule_* come from the rule-based
    difficulty authority. The shadow_* fields are Phase B-01 shadow-only
    next-level success predictions: they never influence difficulty (rules
    stay authoritative) and are null when the shadow model is disabled, the
    game is unsupported, or inference fails.
    """
    session_id: UUID
    game_type: str
    difficulty_level: int
    total_attempts: int
    correct_count: int
    incorrect_count: int
    accuracy_pct: float
    avg_response_time_ms: float
    started_at: str
    completed_at: str
    explanation: Optional[str] = None
    idempotent_replay: bool = False
    recommended_level: int
    difficulty_reason: str
    difficulty_source: Optional[str] = None
    rule_triggered: Optional[str] = None
    rule_version: Optional[str] = None
    shadow_probability: Optional[float] = None
    shadow_model_version: Optional[str] = None
    shadow_reason: Optional[str] = None


class GameHistoryItem(BaseModel):
    """Single session from patient history."""
    session_id: UUID
    game_type: str
    difficulty_level: int
    accuracy_pct: Optional[float] = None
    avg_response_time_ms: Optional[float] = None
    completed_at: Optional[str]


class PatientGameHistoryItem(BaseModel):
    session_id: UUID
    game_type: str
    difficulty_level: int
    score: int
    total_attempts: int
    accuracy_pct: Optional[float] = None
    avg_response_time_ms: Optional[float] = None
    completed_at: Optional[str]


class ContentPackSummary(BaseModel):
    """Metadata for a content pack."""
    id: str
    name: str
    region: str
    description: str
    item_count: int


class MatchItBoardResponse(BaseModel):
    """Generated Match It board configuration."""
    pack_id: str
    pack_name: str
    difficulty_level: int
    pair_count: int
    total_cards: int
    cards: list


class RoutineStep(BaseModel):
    """A single step in a patient's daily routine."""
    step_id: str
    order: int
    time: str
    title_en: str
    title_as: Optional[str] = None
    title_bn: Optional[str] = None
    title_hi: Optional[str] = None
    icon: Optional[str] = None
    hint: Optional[str] = None


class UpdateRoutineRequest(BaseModel):
    """Update patient's custom routine."""
    steps: list[RoutineStep]


class RoutineSequencingBoardResponse(BaseModel):
    """Generated routine sequencing puzzle."""
    difficulty_level: int
    step_count: int
    has_hints: bool
    has_icons: bool
    shuffled_items: list
    correct_sequence: list[str]


class NumberRecallBoardResponse(BaseModel):
    """Generated number-recall memorization board."""
    game_type: str
    difficulty_level: int
    sequence_length: int
    show_seconds_per_item: int
    sequence: list[int]


class OddOneOutItem(BaseModel):
    """One board entry: stable content-pack id + display name."""
    item_id: str
    name: str


class OddOneOutBoardResponse(BaseModel):
    """Generated Odd-One-Out board without answer or explanation fields."""
    game_type: str
    difficulty_level: int
    items: list[OddOneOutItem]
    item_count: int
    target_seconds: int
    group_label: str


class DifficultyEvaluationResponse(BaseModel):
    """Difficulty adjustment recommendation."""
    new_difficulty: Optional[int]
    reason: str
    rule_triggered: Optional[str]
    recent_sessions_reviewed: int
    source: Optional[str] = None
    rule_version: Optional[str] = None
    result: Optional[str] = None
    shadow_probability: Optional[float] = None
    shadow_model_version: Optional[str] = None
    shadow_reason: Optional[str] = None


# ============= Endpoints =============


@router.post("/sessions", response_model=dict)
async def start_game(
    request: StartGameRequest,
    current_user: User = Depends(require_patient),
    db: AsyncSession = Depends(get_db),
):
    """Start a new game session for the patient profile bound to this account."""
    res = await db.execute(
        select(PatientProfile).where(PatientProfile.user_id == current_user.id)
    )
    patient = res.scalar_one_or_none()
    if patient is None:
        raise HTTPException(
            status_code=404,
            detail="No patient profile linked to this account. Create one via POST /patients first.",
        )
    patient_id = patient.id
    await ensure_consent(db, patient_id, "game_data")

    try:
        game_type = GameTypeEnum(request.game_type)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid game_type '{request.game_type}'. Must be one of: "
            + ", ".join(e.value for e in GameTypeEnum),
        )
    session, idempotent_replay = await game_service.start_game_session_with_replay(
        db,
        patient_id=patient_id,
        game_type=game_type,
        difficulty_level=request.difficulty_level,
        content_pack_id=request.content_pack_id,
        routine_id=request.routine_id,
        idempotency_key=request.idempotency_key,
        started_at=request.started_at,
        completed_at=request.completed_at,
    )
    # Snapshot values, then commit: start_game_session only flushes, and reading
    # ORM attributes after commit requires expire_on_commit=False.
    session_id = str(session.id)
    started_at = iso_utc(session.started_at)
    await db.commit()

    return {
        "session_id": session_id,
        "started_at": started_at,
        "idempotent_replay": idempotent_replay,
    }


@router.post("/sessions/{session_id}/actions", response_model=dict)
async def record_action(
    session_id: str,
    request: RecordActionRequest,
    current_user: User = Depends(require_patient),
    db: AsyncSession = Depends(get_db),
):
    """Record a player action within a game session."""
    try:
        sid = UUID(session_id)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid session_id '{session_id}': must be a valid UUID",
        )
    session = await _ensure_owned_session(db, current_user, sid)
    action_data = request.action_data or {}
    response_time_ms = request.response_time_ms
    if response_time_ms is None:
        response_time_ms = action_data.get("response_time_ms")
    try:
        event, idempotent_replay = await game_service.record_game_action(
            db,
            session_id=sid,
            action_type=request.action_type,
            action_data=action_data,
            response_time_ms=response_time_ms,
            idempotency_key=request.idempotency_key,
        )
    except game_service.GameActionValidationError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except game_service.GameSessionCompletedError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    await db.commit()
    return {
        "status": "recorded",
        "event": event,
        "idempotent_replay": idempotent_replay,
    }


@router.post("/sessions/{session_id}/complete", response_model=SessionSummaryResponse)
async def complete_game(
    session_id: str,
    request: Optional[CompleteGameRequest] = None,
    current_user: User = Depends(require_patient),
    db: AsyncSession = Depends(get_db),
):
    """Complete a game session and compute final metrics."""
    try:
        sid = UUID(session_id)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid session_id '{session_id}': must be a valid UUID",
        )
    await _ensure_owned_session(db, current_user, sid)
    completion_request = request or CompleteGameRequest()
    try:
        summary, idempotent_replay = await game_service.complete_game_session(
            db,
            session_id=sid,
            idempotency_key=completion_request.idempotency_key,
            expected_action_ids=completion_request.expected_action_ids,
            completed_at=completion_request.completed_at,
        )
    except game_service.GameActionBarrierError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except game_service.GameCompletionConflictError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except ValueError:
        raise HTTPException(status_code=404, detail="Game session not found")
    return SessionSummaryResponse(
        **summary,
        idempotent_replay=idempotent_replay,
    )


@router.get("/sessions/{session_id}", response_model=dict)
async def get_session(
    session_id: str,
    current_user: User = Depends(require_viewer),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve a game session summary. Access is enforced and audited."""
    from app.deps import ensure_patient_access
    from app.services.compliance_service import ComplianceService

    try:
        sid = UUID(session_id)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid session_id '{session_id}': must be a valid UUID",
        )
    try:
        session_summary = await game_service.get_session_summary(
            db, session_id=sid
        )
    except ValueError:
        raise HTTPException(status_code=404, detail="Game session not found")
    if session_summary.get("patient_id"):
        await ensure_patient_access(db, current_user, session_summary["patient_id"])
        await ComplianceService.log_read_access(
            db, current_user.id, "game_session", session_id)
    return session_summary


@router.get("/me/history", response_model=list[PatientGameHistoryItem])
async def get_my_history(
    limit: int = 10,
    current_user: User = Depends(require_patient),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve the authenticated patient's own recent game sessions."""
    from app.services.compliance_service import ComplianceService

    patient = (
        await db.execute(
            select(PatientProfile).where(PatientProfile.user_id == current_user.id)
        )
    ).scalar_one_or_none()
    if patient is None:
        raise HTTPException(status_code=404, detail="No patient profile linked to this account")
    await ensure_consent(db, patient.id, "game_data")
    await ComplianceService.log_read_access(
        db, current_user.id, "game_history", str(patient.id)
    )
    limit = min(max(limit, 1), 500)
    sessions = (
        await db.execute(
            select(GameSession)
            .where(
                GameSession.patient_id == patient.id,
                GameSession.completed_at.is_not(None),
            )
            .order_by(GameSession.completed_at.desc())
            .limit(limit)
        )
    ).scalars().all()
    return [
        PatientGameHistoryItem(
            session_id=session.id,
            game_type=session.game_type.value,
            difficulty_level=session.difficulty_level,
            score=session.correct_count or 0,
            total_attempts=session.attempts or 0,
            accuracy_pct=session.accuracy_pct,
            avg_response_time_ms=session.avg_response_time_ms,
            completed_at=iso_utc(session.completed_at),
        )
        for session in sessions
    ]


@router.get("/patients/{patient_id}/history", response_model=list[GameHistoryItem])
async def get_patient_history(
    patient_id: str,
    game_type: Optional[str] = None,
    limit: int = 10,
    current_user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve game history for a patient (clinical-tier view). Audited."""
    from app.services.compliance_service import ComplianceService

    pid = _parse_pid(patient_id)
    limit = min(max(limit, 1), 500)
    await ensure_clinical_access(db, current_user, pid)
    await ensure_consent(db, pid, "game_data")
    await ComplianceService.log_read_access(db, current_user.id, "game_history", pid)
    try:
        gt = GameTypeEnum(game_type) if game_type else None
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid game_type '{game_type}'. Must be one of: "
            + ", ".join(e.value for e in GameTypeEnum),
        )
    history = await game_service.get_patient_game_history(
        db, patient_id=pid, game_type=gt, limit=limit
    )
    return [GameHistoryItem(**item) for item in history]


@router.get("/patients/{patient_id}/stats")
async def get_patient_stats(
    patient_id: str,
    days: int = 14,
    current_user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    """Completed-session accuracy and response-time trends (clinical view).

    The legacy ``overall`` aggregate remains available and is explicitly
    labeled as pooled across all completed game types. ``game_metrics`` and
    each trend entry provide per-game detail without changing the old keys.
    """
    from app.services.compliance_service import ComplianceService

    pid = _parse_pid(patient_id)
    await ensure_clinical_access(db, current_user, pid)
    await ensure_consent(db, pid, "game_data")
    await ComplianceService.log_read_access(db, current_user.id, "game_stats", pid)

    days = max(1, min(days, 90))
    now = datetime.now(timezone.utc)
    since = now - timedelta(days=days)
    analytics = await get_game_analytics(db, pid, since, now)
    aggregate = analytics["aggregate"]
    trend = build_daily_trends(
        analytics["sessions"],
        now,
        days,
        include_empty=False,
        include_deltas=True,
    )

    return {
        "patient_id": str(pid),
        "window_days": days,
        "overall": {
            "sessions": aggregate["games_played"],
            "accuracy_pct": aggregate["accuracy_pct"],
            "avg_response_time_ms": aggregate["avg_response_time_ms"],
            "metric_scope": GAME_METRIC_SCOPE,
        },
        "game_metrics": analytics["by_game"],
        "trend": trend,
    }


@router.get("/level-config", response_model=dict)
async def get_level_config(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Full difficulty map {game: {level: params}} for mobile sync.

    Mobile caches this and falls back to its bundled copy offline; the
    table (seeded by migration 0006) is the single source of truth.
    """
    return {
        "config": await level_config_service.get_all_level_config(db),
    }


@router.get("/content-packs", response_model=list[ContentPackSummary])
async def list_content_packs(current_user: User = Depends(get_current_user)):
    """List available content packs for Match It."""
    packs = content_packs.list_content_packs()
    return [ContentPackSummary(**pack) for pack in packs]


@router.get("/content-packs/{pack_id}/board", response_model=MatchItBoardResponse)
async def generate_match_it_board(
    pack_id: str,
    difficulty_level: int = 1,
    session_id: Optional[UUID] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a randomized Match It board (pair count from level config).

    Generic content-pack puzzle: no patient data is served here, so any
    authenticated caller may fetch it (matches mobile/frontend contract).
    Patient scoping + consent are enforced at session start, not on the
    static board.
    """
    session = await _ensure_board_session(
        db,
        current_user,
        session_id,
        GameTypeEnum.MATCH_IT,
        difficulty_level,
        content_pack_id=pack_id,
    )
    if session is not None and isinstance(session.board_snapshot, dict):
        return MatchItBoardResponse(**session.board_snapshot)
    params = await level_config_service.get_level_params(
        db, "match_it", difficulty_level
    )
    try:
        board = content_packs.generate_match_it_board(
            pack_id=pack_id,
            difficulty_level=difficulty_level,
            pair_count=params.get("pairs", 2),
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    if session is not None:
        session.board_snapshot = board
        await db.commit()
    return MatchItBoardResponse(**board)


class ContentItemIn(BaseModel):
    id: str
    name_en: str
    name_as: str = ""
    name_bn: str = ""
    name_hi: str = ""
    category: str = ""
    image_url: str = ""


class ContentPackCreate(BaseModel):
    id: str
    name: str
    region: str = "North East India"
    description: str = ""
    items: list[ContentItemIn]


@router.post("/content-packs", response_model=ContentPackSummary, status_code=201)
async def create_content_pack(
    body: ContentPackCreate,
    current_user: User = Depends(require_admin),
):
    """Admin: register a new Match It themed set (seedable, not hardcoded)."""
    pack = content_packs.register_content_pack(
        pack_id=body.id,
        name=body.name,
        region=body.region,
        description=body.description,
        items=[item.model_dump() for item in body.items],
    )
    return ContentPackSummary(
        id=pack.id,
        name=pack.name,
        region=pack.region,
        description=pack.description,
        item_count=len(pack.items),
    )


@router.post("/patients/{patient_id}/routine")
async def update_patient_routine(
    patient_id: str,
    request: UpdateRoutineRequest,
    current_user: User = Depends(require_caregiver),
    db: AsyncSession = Depends(get_db),
):
    """Update patient's custom daily routine (caregiver editor)."""
    pid = _parse_pid(patient_id)
    await ensure_patient_access(db, current_user, pid)
    steps = [s.model_dump() for s in request.steps]
    updated = await routine_service.update_patient_routine(
        db, patient_id=pid, steps=steps
    )
    return {"status": "updated", "steps": updated}


@router.get("/patients/{patient_id}/routine")
async def get_patient_routine(
    patient_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve patient's daily routine.

    No-implicit-access: the routine is the patient's own daily schedule, so
    only owners, linked caregivers, and staff may read it (matches every
    other patient-data route).
    """
    pid = _parse_pid(patient_id)
    await ensure_patient_access(db, current_user, pid)
    routine = await routine_service.get_patient_routine(
        db, patient_id=pid
    )
    return {"routine": routine}


@router.get("/routine/board", response_model=RoutineSequencingBoardResponse)
async def generate_routine_board(
    patient_id: str,
    difficulty_level: int = 1,
    session_id: Optional[UUID] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a routine sequencing puzzle for a patient (counts from level config)."""
    try:
        pid = UUID(patient_id)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid patient_id '{patient_id}': must be a valid UUID",
        )
    await ensure_patient_access(db, current_user, pid)
    await ensure_consent(db, pid, "game_data")
    session = await _ensure_board_session(
        db,
        current_user,
        session_id,
        GameTypeEnum.ROUTINE_SEQUENCING,
        difficulty_level,
        patient_id=pid,
    )
    if session is not None and isinstance(session.board_snapshot, dict):
        return RoutineSequencingBoardResponse(**session.board_snapshot)
    routine = await routine_service.get_patient_routine(
        db, patient_id=pid
    )
    params = await level_config_service.get_level_params(
        db, "routine_sequencing", difficulty_level
    )
    try:
        board = routine_service.generate_routine_sequencing_board(
            routine,
            difficulty_level=difficulty_level,
            step_count=params.get("steps", 3),
            include_icons=params.get("icons", True),
            include_hints=params.get("hints", difficulty_level <= 2),
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    if session is not None:
        session.board_snapshot = board
        await db.commit()
    return RoutineSequencingBoardResponse(**board)


@router.get("/recall/board", response_model=NumberRecallBoardResponse)
async def generate_number_recall_board(
    difficulty_level: int = 1,
    session_id: Optional[UUID] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a number-recall memorization board (length from level config).

    Generic digit puzzle: no patient data is served here, so any
    authenticated caller may fetch it (matches mobile contract).
    Patient scoping + consent are enforced at session start, not on the
    static board.
    """
    session = await _ensure_board_session(
        db,
        current_user,
        session_id,
        GameTypeEnum.NUMBER_RECALL,
        difficulty_level,
    )
    if session is not None and isinstance(session.board_snapshot, dict):
        return NumberRecallBoardResponse(**session.board_snapshot)
    params = await level_config_service.get_level_params(
        db, "number_recall", difficulty_level
    )
    board = recall_service.generate_number_recall_board(
        difficulty_level=difficulty_level,
        sequence_length=params.get("sequence_length", 3),
        show_seconds_per_item=params.get("show_seconds_per_item", 2),
    )
    if session is not None:
        session.board_snapshot = board
        await db.commit()
    return NumberRecallBoardResponse(**board)


@router.get("/odd-one-out/board", response_model=OddOneOutBoardResponse)
async def generate_odd_one_out_board(
    session_id: UUID,
    difficulty_level: int = 1,
    current_user: User = Depends(require_patient),
    db: AsyncSession = Depends(get_db),
):
    """Generate an Odd-One-Out board for an owned session (counts from level
    config). Same gate as start_game: caller-owned session + active
    `game_data` consent. The answer is held only in private server state."""
    session = await _ensure_board_session(
        db,
        current_user,
        session_id,
        GameTypeEnum.ODD_ONE_OUT,
        difficulty_level,
    )
    res = await db.execute(
        select(PatientProfile).where(PatientProfile.user_id == current_user.id)
    )
    patient = res.scalar_one_or_none()
    if patient is None:
        raise HTTPException(
            status_code=404,
            detail="No patient profile linked to this account. Create one via POST /patients first.",
        )
    await ensure_consent(db, patient.id, "game_data")
    if difficulty_level not in (1, 2, 3):
        raise HTTPException(
            status_code=422, detail="difficulty_level must be 1, 2, or 3"
        )
    if isinstance(session.board_snapshot, dict) and isinstance(session.server_state, dict):
        return OddOneOutBoardResponse(**session.board_snapshot)
    params = await level_config_service.get_level_params(
        db, "odd_one_out", difficulty_level
    )
    board = odd_one_out_service.generate_odd_one_out_board(
        difficulty_level, items=params.get("items"),
    )
    public_board = odd_one_out_service.public_odd_one_out_board(board)
    session.board_snapshot = public_board
    session.server_state = odd_one_out_service.odd_one_out_server_state(board)
    await db.commit()
    return OddOneOutBoardResponse(**public_board)


@router.post("/difficulty/evaluate", response_model=DifficultyEvaluationResponse)
async def evaluate_difficulty(
    patient_id: str,
    game_type: str,
    current_difficulty: int,
    current_user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    """Evaluate if difficulty should adjust for a patient."""
    pid = _parse_pid(patient_id)
    await ensure_patient_access(db, current_user, pid)
    await ensure_consent(db, pid, "game_data")
    try:
        gt = GameTypeEnum(game_type)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid game_type '{game_type}'. Must be one of: "
            + ", ".join(e.value for e in GameTypeEnum),
        )
    evaluation = await difficulty_engine.evaluate_difficulty(
        db,
        patient_id=pid,
        game_type=gt,
        current_difficulty=current_difficulty,
    )
    return DifficultyEvaluationResponse(**evaluation)
