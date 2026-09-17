import uuid
from itertools import product

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app import deps
from app.main import app
from app.models.all_models import AuditLog, CaregiverPatientLink, ConsentRecord, PatientProfile
from app.models.user import RoleEnum, User
from app.services.compliance_service import ComplianceService
from app.routes import patients


@pytest.mark.parametrize("consent_type,scope,guardian,allowed", [
    ("patient_self", "all", None, True),
    ("patient_self", "game_data", None, True),
    ("patient_self", "health_data", None, True),
    ("patient_self", "voice_companion", None, True),
    ("guardian", "all", None, False),
    ("joint", "all", None, False),
    ("patient_self", "guardian", None, False),
    ("patient_self", "joint", None, False),
    ("patient_self", "patient_self", None, False),
    ("patient_self", "unknown", None, False),
    ("game_data", "all", None, False),
    ("patient_self", "all", uuid.uuid4(), False),
])
def test_consent_policy(consent_type, scope, guardian, allowed):
    if allowed:
        ComplianceService.validate_consent_policy(consent_type, scope, guardian)
    else:
        with pytest.raises(HTTPException) as error:
            ComplianceService.validate_consent_policy(consent_type, scope, guardian)
        assert error.value.status_code == 422


@pytest.mark.parametrize("role,relationship,active,self_link", list(product(
    list(RoleEnum), ["family", "asha", "clinician"], [True, False], [True, False],
)))
def test_link_target_policy(role, relationship, active, self_link):
    owner = User(id=uuid.uuid4(), role=RoleEnum.PATIENT, is_active=True)
    target = User(id=owner.id if self_link else uuid.uuid4(), role=role, is_active=active)
    allowed = active and not self_link and (role.value, relationship) in {
        ("family_caregiver", "family"), ("asha_worker", "asha"), ("clinician", "clinician"),
    }
    if allowed:
        patients.validate_caregiver_target(owner, target, relationship)
    else:
        with pytest.raises(HTTPException) as error:
            patients.validate_caregiver_target(owner, target, relationship)
        assert error.value.status_code == 422


@pytest.mark.parametrize("role,own_id", list(product(list(RoleEnum), [True, False])))
def test_profile_binding_policy(role, own_id):
    actor = User(id=uuid.uuid4(), role=role, is_active=True)
    requested = actor.id if own_id else uuid.uuid4()
    if role == RoleEnum.PATIENT and own_id:
        assert patients.resolve_profile_binding(actor, requested) == actor.id
    else:
        with pytest.raises(HTTPException) as error:
            patients.resolve_profile_binding(actor, requested)
        assert error.value.status_code == 403


@pytest.mark.parametrize("role", list(RoleEnum))
def test_profile_binding_without_requested_id(role):
    actor = User(id=uuid.uuid4(), role=role, is_active=True)
    if role == RoleEnum.PATIENT:
        assert patients.resolve_profile_binding(actor, None) == actor.id
    elif role in (RoleEnum.ADMIN, RoleEnum.CLINICIAN, RoleEnum.ASHA_WORKER):
        assert patients.resolve_profile_binding(actor, None) is None
    else:
        with pytest.raises(HTTPException):
            patients.resolve_profile_binding(actor, None)


@pytest.mark.parametrize("role,active,owned", list(product(list(RoleEnum), [True, False], [True, False])))
def test_owner_authority_policy(role, active, owned):
    actor = User(id=uuid.uuid4(), role=role, is_active=active)
    patient = PatientProfile(id=uuid.uuid4(), user_id=actor.id if owned else None)
    allowed = role == RoleEnum.PATIENT and active and owned
    if allowed:
        deps.require_patient_owner(actor, patient)
    else:
        with pytest.raises(HTTPException) as error:
            deps.require_patient_owner(actor, patient)
        assert error.value.status_code == 403


@pytest.mark.asyncio
@pytest.mark.parametrize("tier", ["basic", "clinical"])
async def test_owner_grants_link_and_consent_with_audit(client, db_session, tier):
    owner = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    caregiver = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.FAMILY_CAREGIVER, is_active=True)
    db_session.add_all([owner, caregiver])
    await db_session.commit()
    app.dependency_overrides[deps.get_current_user] = lambda: owner
    response = await client.post("/api/v1/patients", json={"name": "Owner fixture"})
    assert response.status_code == 201, response.text
    pid = response.json()["id"]
    response = await client.post(f"/api/v1/patients/{pid}/caregivers", json={
        "caregiver_id": str(caregiver.id), "relationship_type": "family", "permission_tier": tier,
    })
    assert response.status_code == 201, response.text
    link_id = uuid.UUID(response.json()["id"])
    response = await client.get(f"/api/v1/patients/{pid}/caregivers")
    assert response.status_code == 200, response.text
    assert len(response.json()) == 1
    response = await client.post("/api/v1/compliance/consent", json={"patient_id": pid, "scope": "all"})
    assert response.status_code == 200, response.text
    consent_id = uuid.UUID(response.json()["id"])
    record = await db_session.get(ConsentRecord, consent_id)
    assert record.grantor_id == owner.id
    assert record.guardian_id is None
    response = await client.post(f"/api/v1/compliance/consent/{consent_id}/revoke")
    assert response.status_code == 200, response.text
    assert response.json()["revoked_at"] is not None
    audits = (await db_session.execute(select(AuditLog).where(AuditLog.action == "write"))).scalars().all()
    assert {a.resource_id for a in audits} >= {link_id, consent_id}
    assert all(a.user_id == owner.id for a in audits)
    assert len(audits) == 3


@pytest.mark.asyncio
@pytest.mark.parametrize("consent_type,scope", [
    ("guardian", "all"),
    ("joint", "health_data"),
    ("patient_self", "legacy_scope"),
])
async def test_owner_can_revoke_legacy_consent(client, db_session, consent_type, scope):
    owner = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    guardian = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.FAMILY_CAREGIVER, is_active=True)
    db_session.add_all([owner, guardian])
    await db_session.commit()
    app.dependency_overrides[deps.get_current_user] = lambda: owner
    pid = (await client.post("/api/v1/patients", json={"name": "Legacy owner"})).json()["id"]
    record = ConsentRecord(
        id=uuid.uuid4(), patient_id=uuid.UUID(pid), consent_type=consent_type,
        scope=scope, guardian_id=guardian.id if consent_type != "patient_self" else None,
    )
    db_session.add(record)
    await db_session.commit()
    assert await ComplianceService.verify_consent(db_session, uuid.UUID(pid), scope)
    response = await client.post(f"/api/v1/compliance/consent/{record.id}/revoke")
    assert response.status_code == 200, response.text
    assert response.json()["revoked_at"] is not None
    await db_session.refresh(record)
    assert record.revoked_at is not None
    revoked_at = record.revoked_at
    assert not await ComplianceService.verify_consent(db_session, uuid.UUID(pid), scope)
    repeated = await client.post(f"/api/v1/compliance/consent/{record.id}/revoke")
    assert repeated.status_code == 200, repeated.text
    await db_session.refresh(record)
    assert record.revoked_at == revoked_at
    audits = (await db_session.execute(select(AuditLog).where(
        AuditLog.resource_id == record.id, AuditLog.action == "write",
    ))).scalars().all()
    assert len(audits) == 2
    assert all(a.user_id == owner.id and a.details["operation"] == "revoke" for a in audits)


@pytest.mark.asyncio
@pytest.mark.parametrize("role", [
    RoleEnum.ADMIN, RoleEnum.CLINICIAN, RoleEnum.ASHA_WORKER, RoleEnum.FAMILY_CAREGIVER,
])
async def test_non_owner_cannot_revoke_legacy_consent(client, db_session, role):
    owner = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    actor = User(id=uuid.uuid4(), password_hash="unused", role=role, is_active=True)
    db_session.add_all([owner, actor])
    await db_session.commit()
    app.dependency_overrides[deps.get_current_user] = lambda: owner
    pid = (await client.post("/api/v1/patients", json={"name": "Legacy protected"})).json()["id"]
    record = ConsentRecord(
        id=uuid.uuid4(), patient_id=uuid.UUID(pid), consent_type="guardian",
        scope="all", guardian_id=actor.id,
    )
    db_session.add(record)
    await db_session.commit()
    app.dependency_overrides[deps.get_current_user] = lambda: actor
    response = await client.post(f"/api/v1/compliance/consent/{record.id}/revoke")
    assert response.status_code == 403, response.text
    await db_session.refresh(record)
    assert record.revoked_at is None
    assert not (await db_session.execute(select(AuditLog).where(
        AuditLog.resource_id == record.id, AuditLog.action == "write",
    ))).scalars().all()


@pytest.mark.asyncio
async def test_duplicate_active_link_rejected(client, db_session):
    owner = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    caregiver = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.FAMILY_CAREGIVER, is_active=True)
    db_session.add_all([owner, caregiver])
    await db_session.commit()
    app.dependency_overrides[deps.get_current_user] = lambda: owner
    profile = (await client.post("/api/v1/patients", json={"name": "Dup owner"})).json()
    pid = profile["id"]
    body = {"caregiver_id": str(caregiver.id), "relationship_type": "family"}
    first = await client.post(f"/api/v1/patients/{pid}/caregivers", json=body)
    assert first.status_code == 201, first.text
    second = await client.post(f"/api/v1/patients/{pid}/caregivers", json=body)
    assert second.status_code == 409
    assert second.json()["detail"] == "Caregiver already linked to this patient"
    rows = (await db_session.execute(select(CaregiverPatientLink))).scalars().all()
    assert len(rows) == 1


@pytest.mark.asyncio
async def test_grant_locks_patient_row_for_serialization(client, db_session, monkeypatch):
    owner = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    db_session.add(owner)
    await db_session.commit()
    app.dependency_overrides[deps.get_current_user] = lambda: owner
    pid = (await client.post("/api/v1/patients", json={"name": "Locked owner"})).json()["id"]
    seen = []
    original_execute = db_session.execute

    async def capture(statement, *args, **kwargs):
        if any(item.get("entity") is PatientProfile for item in getattr(statement, "column_descriptions", [])):
            seen.append(statement)
        return await original_execute(statement, *args, **kwargs)

    monkeypatch.setattr(db_session, "execute", capture)
    response = await client.post(f"/api/v1/patients/{pid}/caregivers", json={
        "caregiver_id": str(uuid.uuid4()), "relationship_type": "family"})
    assert response.status_code == 404 or response.status_code == 422
    assert any(statement._for_update_arg is not None for statement in seen)


@pytest.mark.asyncio
async def test_link_grant_fails_closed_on_audit_failure(client, db_session, monkeypatch):
    owner = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    caregiver = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.FAMILY_CAREGIVER, is_active=True)
    db_session.add_all([owner, caregiver])
    await db_session.commit()
    app.dependency_overrides[deps.get_current_user] = lambda: owner
    pid = (await client.post("/api/v1/patients", json={"name": "Fail-closed owner"})).json()["id"]

    async def fail_commit():
        raise RuntimeError("isolated audit persistence failure")

    monkeypatch.setattr(db_session, "commit", fail_commit)
    response = await client.post(f"/api/v1/patients/{pid}/caregivers", json={
        "caregiver_id": str(caregiver.id), "relationship_type": "family"})
    assert response.status_code == 503, response.text
    monkeypatch.undo()
    assert not (await db_session.execute(select(CaregiverPatientLink))).scalars().all()
    assert not (await db_session.execute(select(AuditLog))).scalars().all()


@pytest.mark.asyncio
async def test_revoke_fails_closed_on_audit_failure(client, db_session, monkeypatch):
    owner = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    db_session.add(owner)
    await db_session.commit()
    app.dependency_overrides[deps.get_current_user] = lambda: owner
    pid = (await client.post("/api/v1/patients", json={"name": "Revoke fail-closed"})).json()["id"]
    consent = (await client.post("/api/v1/compliance/consent", json={"patient_id": pid, "scope": "all"})).json()

    async def fail_commit():
        raise RuntimeError("isolated audit persistence failure")

    monkeypatch.setattr(db_session, "commit", fail_commit)
    response = await client.post(f"/api/v1/compliance/consent/{consent['id']}/revoke")
    assert response.status_code == 503, response.text
    monkeypatch.undo()
    stored = await db_session.get(ConsentRecord, uuid.UUID(consent["id"]))
    await db_session.refresh(stored)
    assert stored.revoked_at is None


@pytest.mark.asyncio
async def test_revoke_is_single_record_not_scope_wide(client, db_session):
    owner = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    db_session.add(owner)
    await db_session.commit()
    app.dependency_overrides[deps.get_current_user] = lambda: owner
    pid = (await client.post("/api/v1/patients", json={"name": "Scoped revoke"})).json()["id"]
    for scope in ("game_data", "health_data"):
        created = await client.post("/api/v1/compliance/consent", json={"patient_id": pid, "scope": scope})
        assert created.status_code == 200, created.text
    listed = (await client.get(f"/api/v1/compliance/consent/{pid}")).json()
    target = next(item for item in listed if item["scope"] == "game_data")
    response = await client.post(f"/api/v1/compliance/consent/{target['id']}/revoke")
    assert response.status_code == 200, response.text
    after = (await client.get(f"/api/v1/compliance/consent/{pid}")).json()
    revoked = [item for item in after if item["revoked_at"]]
    active = [item for item in after if not item["revoked_at"]]
    assert len(revoked) == 1 and revoked[0]["id"] == target["id"]
    assert {item["scope"] for item in active} == {"health_data"}
