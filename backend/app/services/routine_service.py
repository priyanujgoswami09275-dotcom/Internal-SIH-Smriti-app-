"""Daily Routine Sequencing Game Service & Caregiver Routine Editor.

Enables caregivers to configure a patient's real daily schedule, and
generates cognitive sequencing puzzles scaled by difficulty (3->6 steps)
with progressive removal of visual hints.
"""
from typing import List, Dict, Any, Optional
import random
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.all_models import PatientProfile
from app.services.level_config_service import default_params


DEFAULT_DAILY_ROUTINE: List[Dict[str, Any]] = [
    {
        "step_id": "wake_up",
        "order": 1,
        "time": "06:00",
        "title_en": "Wake Up",
        "title_as": "পুৱা সাৰ পোৱা",
        "title_bn": "সকালে ঘুম থেকে ওঠা",
        "title_hi": "सुबह जागना",
        "icon": "alarm",
        "hint": "The first thing you do in the morning when the sun rises.",
    },
    {
        "step_id": "brush_teeth",
        "order": 2,
        "time": "06:30",
        "title_en": "Brush Teeth & Wash Face",
        "title_as": "দাঁত ঘঁহা আৰু মুখ ধোৱা",
        "title_bn": "দাঁত মাজা ও মুখ ধোয়া",
        "title_hi": "दांत साफ करना और मुंह धोना",
        "icon": "cleaning_services",
        "hint": "Freshen up with water and toothbrush.",
    },
    {
        "step_id": "morning_tea",
        "order": 3,
        "time": "07:15",
        "title_en": "Morning Bihu Tea & Snack",
        "title_as": "পুৱাৰ বিহু চাহ আৰু জলপান",
        "title_bn": "সকালের বিহু চা ও জলখাবার",
        "title_hi": "सुबह की बिहू चाय और नाश्ता",
        "icon": "coffee",
        "hint": "A warm cup of Assam Bihu tea with biscuit.",
    },
    {
        "step_id": "morning_medicine",
        "order": 4,
        "time": "08:00",
        "title_en": "Take Morning Medicine",
        "title_as": "পুৱাৰ ঔষধ খোৱা",
        "title_bn": "সকালের ওষুধ খাওয়া",
        "title_hi": "सुबह की दवाई लेना",
        "icon": "medication",
        "hint": "Take the prescribed morning pills with water.",
    },
    {
        "step_id": "bath",
        "order": 5,
        "time": "09:30",
        "title_en": "Take a Bath",
        "title_as": "গা ধোৱা",
        "title_bn": "স্নান করা",
        "title_hi": "स्नान करना",
        "icon": "shower",
        "hint": "Freshen up and wear clean clothes.",
    },
    {
        "step_id": "dress_attire",
        "order": 6,
        "time": "09:45",
        "title_en": "Dress in Traditional Attire",
        "title_as": "পৰম্পৰাগত পোছাক পিন্ধা",
        "title_bn": "প্রথাগত পোশাক পরা",
        "title_hi": "पारंपरिक वेशभूषा पहनना",
        "icon": "checkroom",
        "hint": "Wear your traditional dress - Mekhela Sador, Gamosa or shawl.",
    },
    {
        "step_id": "lunch",
        "order": 7,
        "time": "12:30",
        "title_en": "Eat Lunch (Rice & Dal)",
        "title_as": "দুপৰীয়াৰ ভাত খোৱা",
        "title_bn": "দুপুরের খাবার খাওয়া",
        "title_hi": "दोपहर का भोजन",
        "icon": "restaurant",
        "hint": "Enjoy the main midday meal with family.",
    },
    {
        "step_id": "afternoon_rest",
        "order": 8,
        "time": "14:00",
        "title_en": "Afternoon Nap / Rest",
        "title_as": "দুপৰীয়া বিশ্ৰাম / টোপনি",
        "title_bn": "দুপুরের বিশ্রাম",
        "title_hi": "दोपहर का आराम",
        "icon": "hotel",
        "hint": "Rest in a quiet room after lunch.",
    },
    {
        "step_id": "evening_walk",
        "order": 9,
        "time": "17:00",
        "title_en": "Evening Walk & Chat",
        "title_as": "গধূলি ফুৰা আৰু কথা-বতৰা",
        "title_bn": "বিকালে হাঁটা ও গল্প করা",
        "title_hi": "शाम की सैर और बातचीत",
        "icon": "directions_walk",
        "hint": "Step out in the courtyard or verandah.",
    },
    {
        "step_id": "dinner",
        "order": 10,
        "time": "20:00",
        "title_en": "Eat Dinner",
        "title_as": "ৰাতিৰ আহাৰ খোৱা",
        "title_bn": "রাতের খাবার খাওয়া",
        "title_hi": "रात का खाना",
        "icon": "dinner_dining",
        "hint": "Light night meal.",
    },
    {
        "step_id": "sleep",
        "order": 11,
        "time": "21:30",
        "title_en": "Go to Sleep",
        "title_as": "শুবলৈ যোৱা",
        "title_bn": "ঘুমাতে যাওয়া",
        "title_hi": "सोने जाना",
        "icon": "bedtime",
        "hint": "Turn off the lights and rest for the night.",
    },
]

# Step counts/flags resolve from game_level_config (DEFAULT_LEVEL_CONFIG
# fallback). Do not reintroduce a local map — the table is the single
# source of truth.
def _config_for_level(difficulty_level: int) -> Dict[str, Any]:
    cfg = default_params("routine_sequencing", difficulty_level)
    return {
        "steps": cfg.get("steps", 3),
        # Icons stay on at every level: accessibility aid, hard mode
        # removes hints, not icons (see GameLevelConfig seeds).
        "icons": cfg.get("icons", True),
        "hints": cfg.get("hints", difficulty_level <= 2),
    }


async def get_patient_routine(db: AsyncSession, patient_id: UUID) -> List[Dict[str, Any]]:
    """Retrieve custom routine for patient, or fallback to default."""
    result = await db.execute(select(PatientProfile).where(PatientProfile.id == patient_id))
    patient = result.scalar_one_or_none()
    if patient and patient.routine:
        return patient.routine.get("steps", DEFAULT_DAILY_ROUTINE)
    return DEFAULT_DAILY_ROUTINE


async def update_patient_routine(
    db: AsyncSession, patient_id: UUID, steps: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """Caregiver routine editor: save custom steps to PatientProfile.routine."""
    result = await db.execute(select(PatientProfile).where(PatientProfile.id == patient_id))
    patient = result.scalar_one_or_none()
    if not patient:
        raise ValueError("Patient not found")

    # Ensure chronological order numbering 1..N
    sorted_steps = sorted(steps, key=lambda s: s.get("time", "00:00"))
    for idx, s in enumerate(sorted_steps, 1):
        s["order"] = idx

    patient.routine = {"steps": sorted_steps}
    await db.commit()
    await db.refresh(patient)
    return sorted_steps


def generate_routine_sequencing_board(
    routine_steps: List[Dict[str, Any]],
    difficulty_level: int = 1,
    step_count: Optional[int] = None,
    include_icons: Optional[bool] = None,
    include_hints: Optional[bool] = None,
) -> Dict[str, Any]:
    """Generate a routine sequencing puzzle with shuffled steps according to difficulty.

    Counts/flags resolve from game_level_config when omitted (routes pass the
    DB-resolved values); the parameters exist so offline/pure callers stay sync.
    """
    cfg = _config_for_level(difficulty_level)
    if step_count is None:
        step_count = cfg["steps"]
    if include_icons is None:
        include_icons = cfg["icons"]
    if include_hints is None:
        include_hints = cfg["hints"]
    sorted_routine = sorted(routine_steps, key=lambda s: s["order"])
    if not sorted_routine:
        raise ValueError("Routine must contain at least one playable step")
    step_count = max(1, min(step_count, len(sorted_routine)))

    # Pick a contiguous or well-spaced subset of steps to sequence
    if len(sorted_routine) > step_count:
        start_idx = random.randint(0, len(sorted_routine) - step_count)
        subset = sorted_routine[start_idx : start_idx + step_count]
    else:
        subset = sorted_routine[:step_count]

    # Target correct sequence order
    correct_sequence = [s["step_id"] for s in subset]

    # Prepare puzzle items (with hint level based on difficulty)
    puzzle_items = []
    for s in subset:
        item = {
            "step_id": s["step_id"],
            "title_en": s["title_en"],
            "title_as": s.get("title_as", s["title_en"]),
            "title_bn": s.get("title_bn", s["title_en"]),
            "title_hi": s.get("title_hi", s["title_en"]),
            "approx_time": s.get("time", ""),
            "icon": s.get("icon", "schedule") if include_icons else None,
            "hint": s.get("hint", "") if difficulty_level == 1 else None,
        }
        puzzle_items.append(item)

    # Shuffle for the player
    shuffled_items = list(puzzle_items)
    while len(shuffled_items) > 1 and [s["step_id"] for s in shuffled_items] == correct_sequence:
        random.shuffle(shuffled_items)

    return {
        "difficulty_level": difficulty_level,
        "step_count": step_count,
        "has_hints": include_hints,
        "has_icons": include_icons,
        "shuffled_items": shuffled_items,
        "correct_sequence": correct_sequence,
    }


def validate_routine_sequence(
    submitted_order: List[str], correct_sequence: List[str]
) -> Dict[str, Any]:
    """Validate submitted sequence against target.

    Computes correctness, correct/incorrect positions, and error pattern.
    """
    total = len(correct_sequence)
    correct_positions = 0
    errors = []

    for idx, step_id in enumerate(submitted_order):
        if idx < total and step_id == correct_sequence[idx]:
            correct_positions += 1
        else:
            actual_pos = correct_sequence.index(step_id) if step_id in correct_sequence else -1
            errors.append({
                "step_id": step_id,
                "placed_at": idx,
                "expected_at": actual_pos,
            })

    is_perfect = (correct_positions == total)
    accuracy_pct = round((correct_positions / total) * 100.0, 1) if total > 0 else 0.0

    return {
        "is_perfect": is_perfect,
        "accuracy_pct": accuracy_pct,
        "correct_count": correct_positions,
        "total_steps": total,
        "errors": errors,
    }
