import httpx
import pytest

import smoke_e2e


@pytest.mark.parametrize("phone,password", [(None, None), ("test-clinician", None), (None, "test-password"), ("", "test-password")])
def test_smoke_requires_clinician_credentials_before_client(monkeypatch, capsys, phone, password):
    for name, value in (("SMOKE_CLINICIAN_PHONE", phone), ("SMOKE_CLINICIAN_PASSWORD", password)):
        if value is None:
            monkeypatch.delenv(name, raising=False)
        else:
            monkeypatch.setenv(name, value)

    def no_client(**kwargs):
        pytest.fail("Missing credentials must fail before creating an HTTP client")

    monkeypatch.setattr(smoke_e2e.httpx, "Client", no_client)
    with pytest.raises(SystemExit) as exc:
        smoke_e2e.main()
    assert exc.value.code == 1
    output = capsys.readouterr()
    message = output.out + output.err
    assert "SMOKE_CLINICIAN_PHONE" in message
    assert "SMOKE_CLINICIAN_PASSWORD" in message
    assert "already-provisioned" in message
    assert "test-password" not in message


@pytest.mark.parametrize("status,role", [(401, None), (200, "patient"), (200, "admin")])
def test_smoke_invalid_clinician_stops_before_public_signup(monkeypatch, capsys, status, role):
    monkeypatch.setenv("SMOKE_CLINICIAN_PHONE", "test-clinician")
    monkeypatch.setenv("SMOKE_CLINICIAN_PASSWORD", "test-password")
    requests = []

    def handle(request):
        requests.append((request.method, request.url.path))
        if request.url.path == "/health":
            return httpx.Response(200, json={"status": "ok"})
        if request.url.path == "/api/v1/auth/login":
            if status != 200:
                return httpx.Response(status, json={"detail": "test-password"})
            return httpx.Response(200, json={"access_token": "test-token", "refresh_token": "test-refresh"})
        if request.url.path == "/api/v1/auth/me":
            return httpx.Response(200, json={"role": role})
        pytest.fail("Clinician validation must finish before public signup")

    client_type = httpx.Client
    monkeypatch.setattr(smoke_e2e.httpx, "Client", lambda **kwargs: client_type(
        **kwargs, transport=httpx.MockTransport(handle)))
    with pytest.raises(SystemExit) as exc:
        smoke_e2e.main()
    assert exc.value.code == 1
    assert ("POST", "/api/v1/auth/register") not in requests
    output = capsys.readouterr()
    message = output.out + output.err
    assert "clinician" in message.lower()
    assert "test-password" not in message
    assert "test-token" not in message
    assert "test-refresh" not in message
