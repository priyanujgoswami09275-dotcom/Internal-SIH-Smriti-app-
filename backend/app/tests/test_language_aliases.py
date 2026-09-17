"""Phase 3 language naming/gating tests: manipuri canonical, meitei alias, garo absent.

"meitei" is the mobile display name for Manipuri and must resolve identically
on every provider; Garo has no provider code anywhere and is hard-gated in
the mobile picker (VoiceLanguages.hardUnsupported).
"""
import pytest

from app.services.language_service import (
    AI4BHARAT_LANG_CODES,
    LANG_CODES,
    SARVAM_LANG_CODES,
    Ai4BharatLanguageService,
    BhashiniLanguageService,
    MockLanguageService,
    SarvamLanguageService,
    UnsupportedLanguageError,
)


def test_meitei_alias_matches_manipuri_everywhere():
    assert LANG_CODES["meitei"] == LANG_CODES["manipuri"] == "mni"
    assert SARVAM_LANG_CODES["meitei"] == SARVAM_LANG_CODES["manipuri"] == "mni-IN"
    assert AI4BHARAT_LANG_CODES["meitei"] == AI4BHARAT_LANG_CODES["manipuri"] == "mni_Mtei"


def test_garo_has_no_provider_code():
    assert "garo" not in LANG_CODES
    assert "garo" not in SARVAM_LANG_CODES
    assert "garo" not in AI4BHARAT_LANG_CODES
    assert "garo" not in MockLanguageService().supported_languages()


def test_providers_accept_meitei_case_insensitive():
    sarvam = SarvamLanguageService(api_key="t")
    assert sarvam._lang_code("Meitei") == "mni-IN"
    ai4bharat = Ai4BharatLanguageService(api_token="t")
    assert ai4bharat._lang_code("MEITEI") == "mni_Mtei"
    bhashini = BhashiniLanguageService(api_key="k", user_id="u")
    assert bhashini._lang_code("meitei") == "mni"


def test_providers_reject_garo_as_unsupported():
    sarvam = SarvamLanguageService(api_key="t")
    with pytest.raises(UnsupportedLanguageError):
        sarvam._lang_code("garo")
    ai4bharat = Ai4BharatLanguageService(api_token="t")
    with pytest.raises(UnsupportedLanguageError):
        ai4bharat._lang_code("garo")
    bhashini = BhashiniLanguageService(api_key="k", user_id="u")
    with pytest.raises(UnsupportedLanguageError):
        bhashini._lang_code("garo")


def test_supported_sets_advertise_alias_never_garo():
    assert "meitei" in SarvamLanguageService(api_key="t").supported_languages()
    assert "meitei" in Ai4BharatLanguageService(api_token="t").supported_languages()
    assert "meitei" in MockLanguageService().supported_languages()
