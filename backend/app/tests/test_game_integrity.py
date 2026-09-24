import pytest

from app.services import content_packs, recall_service, routine_service


def test_match_board_clamps_pair_count_to_playable_inventory(monkeypatch):
    pack = content_packs.ContentPack(
        id="integrity_tiny_pack",
        name="Integrity Tiny Pack",
        region="Test",
        description="Two-item generator fixture",
        items=[
            content_packs.ContentItem("one", "One", "এক", "এক", "एक", "test", ""),
            content_packs.ContentItem("two", "Two", "দুই", "দুই", "दो", "test", ""),
        ],
    )
    monkeypatch.setitem(content_packs.NER_CONTENT_PACKS, pack.id, pack)

    for requested, expected in ((-4, 1), (0, 1), (99, 2)):
        board = content_packs.generate_match_it_board(
            pack_id=pack.id,
            difficulty_level=3,
            pair_count=requested,
        )

        assert board["pair_count"] == expected
        assert board["total_cards"] == expected * 2
        assert len(board["cards"]) == expected * 2


def test_routine_board_clamps_step_count_to_available_steps():
    routine = [
        dict(routine_service.DEFAULT_DAILY_ROUTINE[0]),
        dict(routine_service.DEFAULT_DAILY_ROUTINE[1]),
    ]

    for requested, expected in ((-3, 1), (0, 1), (99, 2)):
        board = routine_service.generate_routine_sequencing_board(
            routine,
            difficulty_level=3,
            step_count=requested,
        )

        assert board["step_count"] == expected
        assert len(board["shuffled_items"]) == expected
        assert len(board["correct_sequence"]) == expected


@pytest.mark.parametrize(
    ("requested", "expected"),
    ((-5, 1), (0, 1), (3, 3), (99, 10)),
)
def test_recall_board_clamps_sequence_length_to_playable_range(requested, expected):
    board = recall_service.generate_number_recall_board(
        difficulty_level=3,
        sequence_length=requested,
    )

    assert board["sequence_length"] == expected
    assert len(board["sequence"]) == expected
