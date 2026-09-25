import uuid

import pytest

from app.models.all_models import CaregiverPatientLink, PermissionTierEnum, RelationshipTypeEnum
from app.tests.conftest import create_consented_patient, provision_staff_user

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
DASHBOARD = "/api/v1/dashboard"


async def _login(client, user):
    response = await client.post(
        f"{AUTH}/login",
        json={"phone": user["phone"], "password": "Passw0rd123"},
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


async def _profile_without_consent(client, name):
    user = await client.post(
        f"{AUTH}/register",
        json={
            "phone": f"+91{uuid.uuid4().int % 10**10}",
            "password": "Passw0rd123",
            "role": "patient",
            "preferred_language": "english",
        },
    )
    assert user.status_code == 201, user.text
    headers = await _login(client, user.json())
    profile = await client.post(
        PATIENTS,
        headers=headers,
        json={"name": name, "region": "assam"},
    )
    assert profile.status_code == 201, profile.text
    return profile.json(), headers


@pytest.mark.asyncio
@pytest.mark.parametrize("role", ["clinician", "admin"])
async def test_unlinked_clinical_staff_roster_includes_entitled_patients(
    client, role
):
    first = await create_consented_patient(client, f"Clinical {role} One")
    second = await create_consented_patient(client, f"Clinical {role} Two")
    staff = await provision_staff_user(role=role)
    headers = await _login(client, staff)

    response = await client.get(
        f"{DASHBOARD}/caregivers/{staff['id']}/patients",
        headers=headers,
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert {item["patient_id"] for item in body} == {first["id"], second["id"]}
    assert {item["permission_tier"] for item in body} == {"clinical"}


@pytest.mark.asyncio
async def test_asha_roster_is_assigned_link_scoped(client, db_session):
    assigned = await create_consented_patient(client, "Assigned Patient")
    unassigned = await create_consented_patient(client, "Unassigned Patient")
    asha = await provision_staff_user(role="asha_worker")
    db_session.add(
        CaregiverPatientLink(
            caregiver_id=uuid.UUID(asha["id"]),
            patient_id=uuid.UUID(assigned["id"]),
            relationship_type=RelationshipTypeEnum.ASHA,
            permission_tier=PermissionTierEnum.CLINICAL,
            is_active=True,
        )
    )
    db_session.add(
        CaregiverPatientLink(
            caregiver_id=uuid.UUID(asha["id"]),
            patient_id=uuid.UUID(unassigned["id"]),
            relationship_type=RelationshipTypeEnum.ASHA,
            permission_tier=PermissionTierEnum.CLINICAL,
            is_active=False,
        )
    )
    await db_session.commit()
    headers = await _login(client, asha)

    response = await client.get(
        f"{DASHBOARD}/caregivers/{asha['id']}/patients",
        headers=headers,
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert [item["patient_id"] for item in body] == [assigned["id"]]
    assert body[0]["relationship_type"] == "asha"
    assert body[0]["permission_tier"] == "clinical"


@pytest.mark.asyncio
async def test_family_roster_remains_link_scoped(client, db_session):
    linked = await create_consented_patient(client, "Linked Family Patient")
    other = await create_consented_patient(client, "Other Family Patient")
    family_response = await client.post(
        f"{AUTH}/register",
        json={
            "phone": f"+91{uuid.uuid4().int % 10**10}",
            "password": "Passw0rd123",
            "role": "family_caregiver",
            "preferred_language": "english",
        },
    )
    assert family_response.status_code == 201, family_response.text
    family = family_response.json()
    db_session.add(
        CaregiverPatientLink(
            caregiver_id=uuid.UUID(family["id"]),
            patient_id=uuid.UUID(linked["id"]),
            relationship_type=RelationshipTypeEnum.FAMILY,
            permission_tier=PermissionTierEnum.BASIC,
            is_active=True,
        )
    )
    await db_session.commit()
    headers = await _login(client, family)

    response = await client.get(
        f"{DASHBOARD}/caregivers/{family['id']}/patients",
        headers=headers,
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert [item["patient_id"] for item in body] == [linked["id"]]
    assert other["id"] not in {item["patient_id"] for item in body}


@pytest.mark.asyncio
async def test_risk_screening_consent_preflight_reports_required_then_granted(
    client,
):
    profile, owner_headers = await _profile_without_consent(client, "Consent Preflight")
    clinician = await provision_staff_user(role="clinician")
    clinician_headers = await _login(client, clinician)
    endpoint = f"{DASHBOARD}/patients/{profile['id']}/risk-screening/consent"

    required = await client.get(endpoint, headers=clinician_headers)
    assert required.status_code == 200, required.text
    assert required.json() == {
        "patient_id": profile["id"],
        "permission_tier": "clinical",
        "required_scope": "health_data",
        "health_data_consent": False,
        "consent_state": "required",
    }

    granted = await client.post(
        f"/api/v1/compliance/consent",
        headers=owner_headers,
        json={
            "patient_id": profile["id"],
            "consent_type": "patient_self",
            "scope": "health_data",
        },
    )
    assert granted.status_code == 200, granted.text

    after_grant = await client.get(endpoint, headers=clinician_headers)
    assert after_grant.status_code == 200, after_grant.text
    assert after_grant.json()["health_data_consent"] is True
    assert after_grant.json()["consent_state"] == "granted"
