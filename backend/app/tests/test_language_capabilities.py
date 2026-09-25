import pytest

from app.routes.language import TranslationRequest, language_status, translate_text
from app.services.language_service import MockLanguageService, SarvamLanguageService


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("language", "asr", "nmt", "tts"),
    [
        ("assamese", True, True, False),
        ("bengali", True, True, True),
        ("english", True, True, True),
        ("manipuri", True, True, False),
        ("bodo", True, True, False),
        ("nepali", True, True, False),
        ("khasi", False, False, False),
        ("mizo", False, False, False),
    ],
)
async def test_status_reports_each_sarvam_operation_independently(
    language, asr, nmt, tts
):
    service = SarvamLanguageService(api_key="test-key")
    payload = await language_status(lang_service=service)
    capabilities = payload.get("capabilities", {})

    assert capabilities.get("asr", {}).get("provider") == "sarvam"
    assert capabilities.get("nmt", {}).get("provider") == "sarvam"
    assert capabilities.get("tts", {}).get("provider") == "sarvam"
    assert (language in capabilities.get("asr", {}).get("languages", [])) is asr
    assert (language in capabilities.get("nmt", {}).get("languages", [])) is nmt
    assert (language in capabilities.get("tts", {}).get("languages", [])) is tts


@pytest.mark.asyncio
async def test_status_keeps_legacy_provider_and_union_fields():
    service = SarvamLanguageService(api_key="test-key")
    payload = await language_status(lang_service=service)

    assert payload["provider"] == service.name
    assert payload["supported_languages"] == service.supported_languages()
    assert "assamese" in payload["supported_languages"]
    tts_languages = payload.get("capabilities", {}).get("tts", {}).get("languages", [])
    assert "assamese" not in tts_languages


@pytest.mark.asyncio
async def test_mock_status_labels_each_operation_as_simulated():
    service = MockLanguageService()
    payload = await language_status(lang_service=service)
    capabilities = payload.get("capabilities", {})

    assert set(capabilities) == {"asr", "nmt", "tts"}
    for operation in ("asr", "nmt", "tts"):
        assert capabilities[operation]["provider"] == "mock"
        assert capabilities[operation]["simulated"] is True
        assert "assamese" in capabilities[operation]["languages"]


@pytest.mark.asyncio
async def test_translation_response_preserves_its_provider():
    service = MockLanguageService()
    payload = await translate_text(
        TranslationRequest(
            text="Hello",
            source_language="english",
            target_language="assamese",
        ),
        lang_service=service,
        current_user=object(),
    )

    assert payload["provider"] == "mock"
    assert payload["simulated"] is True
