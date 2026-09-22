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
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel

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

router = APIRouter(prefix="/games", tags=["games"])


# ============= Role dependencies =============
require_patient = require_role("patient")
require_caregiver = require_role("family_caregiver", "asha_worker")
require_staff = require_role("family_caregiver", "asha_worker", "clinician")
require_viewer = require_role("patient", "family_caregiver", "asha_worker", "clinician")
require_admin = require_role("admin")


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


# ============= Schemas =============


class StartGameRequest(BaseModel):
    """Start a new game session."""
    game_type: str  # "match_it" | "routine_sequencing" | "number_recall" | "odd_one_out"
    difficulty_level: int = 1
    content_pack_id: Optional[str] = None  # For Match It
    routine_id: Optional[str] = None  # For Routine Sequencing


class RecordActionRequest(BaseModel):
    """Record a single player action."""
    action_type: str
    action_data: dict
    is_correct: Optional[bool] = None
    response_time_ms: Optional[int] = None


class SessionSummaryResponse(BaseModel):
    """Completed game session summary."""
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


class GameHistoryItem(BaseModel):
    """Single session from patient history."""
    session_id: UUID
    game_type: str
    difficulty_level: int
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
    """Generated Odd-One-Out board. The answer stays server-side in
    ``session.board_snapshot`` and is never serialized here."""
    game_type: str
    difficulty_level: int
    items: list[OddOneOutItem]
    item_count: int
    target_seconds: int
    group_label: str
    explanation: str


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
    session = await game_service.start_game_session(
        db,
        patient_id=patient_id,
        game_type=game_type,
        difficulty_level=request.difficulty_level,
        content_pack_id=request.content_pack_id,
        routine_id=request.routine_id,
    )
    # Snapshot values, then commit: start_game_session only flushes, and reading
    # ORM attributes after commit requires expire_on_commit=False.
    session_id = str(session.id)
    started_at = session.started_at.isoformat()
    await db.commit()

    return {
        "session_id": session_id,
        "started_at": started_at,
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
    is_correct = request.is_correct
    response_time_ms = request.response_time_ms
    server_fields: dict = {}
    if (
        session.game_type == GameTypeEnum.ODD_ONE_OUT
        and request.action_type == "select_odd_item"
    ):
        # Server-truth scoring: correctness derives from the stored board
        # snapshot, never from client claims. Other games honor the client
        # verdict as before.
        snapshot = session.board_snapshot or {}
        answer_item_id = snapshot.get("answer_item_id")
        if not answer_item_id:
            raise HTTPException(
                status_code=422,
                detail="no server board for this session; fetch board first",
            )
        action_data = request.action_data or {}
        if response_time_ms is None:
            response_time_ms = action_data.get("response_time_ms")
        verdict = odd_one_out_service.score_odd_one_out(
            action_data.get("selected_item_id"), answer_item_id
        )
        is_correct = verdict["correct"]
        server_fields = {
            "error_category": verdict["error_category"],
            "opportunity": verdict["opportunity"],
        }
    event = await game_service.record_game_action(
        db,
        session_id=sid,
        action_type=request.action_type,
        action_data=request.action_data,
        is_correct=is_correct,
        response_time_ms=response_time_ms,
    )
    if server_fields:
        # Persist the server verdict + error_category in the stored event.
        # Reassign — don't mutate — so change detection persists on flush.
        updated_log = list(session.raw_event_log or [])
        if updated_log:
            patched = dict(updated_log[-1])
            patched.update(server_fields)
            updated_log[-1] = patched
            session.raw_event_log = updated_log
            await db.flush()
    await db.commit()  # record_game_action only flushes; persist before returning
    if server_fields:
        event = {**event, **server_fields}

    return {"status": "recorded", "event": event}


@router.post("/sessions/{session_id}/complete", response_model=SessionSummaryResponse)
async def complete_game(
    session_id: str,
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
    try:
        summary = await game_service.complete_game_session(db, session_id=sid)
    except ValueError:
        raise HTTPException(status_code=404, detail="Game session not found")
    return SessionSummaryResponse(**summary)


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

    await ensure_clinical_access(db, current_user, UUID(patient_id))
    await ensure_consent(db, UUID(patient_id), "game_data")
    await ComplianceService.log_read_access(db, current_user.id, "game_history", patient_id)
    try:
        gt = GameTypeEnum(game_type) if game_type else None
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid game_type '{game_type}'. Must be one of: "
            + ", ".join(e.value for e in GameTypeEnum),
        )
    history = await game_service.get_patient_game_history(
        db, patient_id=UUID(patient_id), game_type=gt, limit=limit
    )
    return [GameHistoryItem(**item) for item in history]


@router.get("/patients/{patient_id}/stats")
async def get_patient_stats(
    patient_id: str,
    days: int = 14,
    current_user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    """Accuracy + response-time trends across both games (clinical-tier view).

    Aggregates completed sessions per day: overall accuracy, average response
    time, sessions played. Audited read.
    """
    from datetime import timedelta, datetime, timezone
    from collections import defaultdict
    from app.services.compliance_service import ComplianceService

    pid = UUID(patient_id)
    await ensure_clinical_access(db, current_user, pid)
    await ensure_consent(db, pid, "game_data")
    await ComplianceService.log_read_access(db, current_user.id, "game_stats", pid)

    days = max(1, min(days, 90))
    since = datetime.now(timezone.utc) - timedelta(days=days)
    stmt = (
        select(GameSession)
        .where(GameSession.patient_id == pid, GameSession.started_at >= since)
        .order_by(GameSession.started_at.asc())
    )
    sessions = (await db.execute(stmt)).scalars().all()

    by_day: dict = defaultdict(lambda: {"attempts": 0, "correct": 0, "times": [], "games": 0})
    for s in sessions:
        day = (s.started_at if s.started_at.tzinfo else s.started_at.replace(
            tzinfo=timezone.utc)).astimezone(timezone.utc).date().isoformat()
        d = by_day[day]
        d["attempts"] += s.attempts or 0
        d["correct"] += s.correct_count or 0
        if s.avg_response_time_ms is not None:
            d["times"].append(s.avg_response_time_ms)
        d["games"] += 1

    trend = []
    prev_accuracy = None
    for day in sorted(by_day):
        d = by_day[day]
        accuracy = round(d["correct"] / d["attempts"] * 100.0, 1) if d["attempts"] else None
        entry = {
            "date": day,
            "games": d["games"],
            "accuracy_pct": accuracy,
            "avg_response_time_ms": round(sum(d["times"]) / len(d["times"]), 1)
            if d["times"] else None,
        }
        if accuracy is not None and prev_accuracy is not None:
            entry["accuracy_delta_pct"] = round(accuracy - prev_accuracy, 1)
        if accuracy is not None:
            prev_accuracy = accuracy
        trend.append(entry)

    total_attempts = sum(d["attempts"] for d in by_day.values())
    total_correct = sum(d["correct"] for d in by_day.values())
    all_times = [t for d in by_day.values() for t in d["times"]]
    return {
        "patient_id": str(pid),
        "window_days": days,
        "overall": {
            "sessions": len(sessions),
            "accuracy_pct": round(total_correct / total_attempts * 100.0, 1)
            if total_attempts else None,
            "avg_response_time_ms": round(sum(all_times) / len(all_times), 1)
            if all_times else None,
        },
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
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a randomized Match It board (pair count from level config).

    Generic content-pack puzzle: no patient data is served here, so any
    authenticated caller may fetch it (matches mobile/frontend contract).
    Patient scoping + consent are enforced at session start, not on the
    static board.
    """
    params = await level_config_service.get_level_params(
        db, "match_it", difficulty_level
    )
    board = content_packs.generate_match_it_board(
        pack_id=pack_id,
        difficulty_level=difficulty_level,
        pair_count=params.get("pairs", 2),
    )
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
    await ensure_patient_access(db, current_user, UUID(patient_id))
    steps = [s.model_dump() for s in request.steps]
    updated = await routine_service.update_patient_routine(
        db, patient_id=UUID(patient_id), steps=steps
    )
    return {"status": "updated", "steps": updated}


@router.get("/patients/{patient_id}/routine")
async def get_patient_routine(
    patient_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve patient's daily routine."""
    routine = await routine_service.get_patient_routine(
        db, patient_id=UUID(patient_id)
    )
    return {"routine": routine}


@router.get("/routine/board", response_model=RoutineSequencingBoardResponse)
async def generate_routine_board(
    patient_id: str,
    difficulty_level: int = 1,
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
    routine = await routine_service.get_patient_routine(
        db, patient_id=pid
    )
    params = await level_config_service.get_level_params(
        db, "routine_sequencing", difficulty_level
    )
    board = routine_service.generate_routine_sequencing_board(
        routine,
        difficulty_level=difficulty_level,
        step_count=params.get("steps", 3),
        include_icons=params.get("icons", True),
        include_hints=params.get("hints", difficulty_level <= 2),
    )
    return RoutineSequencingBoardResponse(**board)


@router.get("/recall/board", response_model=NumberRecallBoardResponse)
async def generate_number_recall_board(
    difficulty_level: int = 1,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a number-recall memorization board (length from level config).

    Generic digit puzzle: no patient data is served here, so any
    authenticated caller may fetch it (matches mobile contract).
    Patient scoping + consent are enforced at session start, not on the
    static board.
    """
    params = await level_config_service.get_level_params(
        db, "number_recall", difficulty_level
    )
    board = recall_service.generate_number_recall_board(
        difficulty_level=difficulty_level,
        sequence_length=params.get("sequence_length", 3),
        show_seconds_per_item=params.get("show_seconds_per_item", 2),
    )
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
    `game_data` consent. The full board (including `answer_item_id`) is stored
    on `session.board_snapshot`; the response withholds the answer."""
    session = await _ensure_owned_session(db, current_user, session_id)
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
    params = await level_config_service.get_level_params(
        db, "odd_one_out", difficulty_level
    )
    board = odd_one_out_service.generate_odd_one_out_board(
        difficulty_level, items=params.get("items"),
    )
    # Reassign — don't mutate — so SQLAlchemy persists the snapshot on commit.
    session.board_snapshot = dict(board)
    await db.commit()
    return OddOneOutBoardResponse(
        game_type=board["game_type"],
        difficulty_level=board["difficulty_level"],
        items=board["items"],
        item_count=board["item_count"],
        target_seconds=board["target_seconds"],
        group_label=board["group_label"],
        explanation=board["explanation"],
    )


@router.post("/difficulty/evaluate", response_model=DifficultyEvaluationResponse)
async def evaluate_difficulty(
    patient_id: str,
    game_type: str,
    current_difficulty: int,
    current_user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    """Evaluate if difficulty should adjust for a patient."""
    pid = UUID(patient_id)
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
