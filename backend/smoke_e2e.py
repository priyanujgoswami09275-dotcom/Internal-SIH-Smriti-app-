"""End-to-end API smoke test against a live backend + real database.

Usage:
    DATABASE_URL=postgresql+psycopg://postgres@localhost:5433/eldercare \
        uvicorn app.main:app --port 8000 &      # backend, real PG
    python smoke_e2e.py                          # base URL from API_BASE_URL or :8000

Walks the full product flow with three actors (patient, family_caregiver,
clinician): auth -> patient profile -> game session -> reminders ->
caregiver dashboard -> offline sync -> companion config/chat -> RAG ->
DPDP consent. Prints PASS/FAIL per step; exits non-zero on any failure.
"""
import json
import os
import sys
import uuid

import httpx

BASE = os.getenv("API_BASE_URL", "http://localhost:8000").rstrip("/")
PASS, FAIL = 0, 0


def check(name, resp, expect_status=None, expect_key=None):
    """Assert an HTTP response; print FAIL (with detail) and return parsed body."""
    global PASS, FAIL
    ok = True
    detail = ""
    if expect_status is not None and resp.status_code != expect_status:
        ok = False
        detail = f"status {resp.status_code} (expected {expect_status})"
    body = None
    if ok:
        try:
            body = resp.json()
        except Exception:
            body = None
        if expect_key is not None:
            found = body is not None and expect_key in body
            if not found:
                ok = False
                detail = f"missing key '{expect_key}' in {json.dumps(body)[:200]}"
    if ok:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        print(f"  [FAIL] {name} — {detail}")
        if resp.status_code >= 400:
            print(f"          server said: {resp.text[:300]}")
    return body


def main():
    clinician_phone = os.getenv("SMOKE_CLINICIAN_PHONE", "").strip()
    clinician_password = os.getenv("SMOKE_CLINICIAN_PASSWORD", "")
    if not clinician_phone or not clinician_password:
        print("SMOKE_CLINICIAN_PHONE and SMOKE_CLINICIAN_PASSWORD are required for an already-provisioned test clinician.", file=sys.stderr)
        sys.exit(1)
    pid_os = os.getpid()
    actors = [("patient", "patient"), ("caregiver", "family_caregiver")]
    phones = {key: f"91{pid_os}{i:03d}" for i, (key, _) in enumerate(actors, 1)}
    tokens = {}
    patient_id = None

    # 120s: free-tier LLM replies (companion chat) observed at ~50s+ live.
    with httpx.Client(base_url=BASE, timeout=120) as c:
        check("GET /health", c.get("/health"), 200, "status")

        r = c.post("/api/v1/auth/login", json={
            "phone": clinician_phone, "password": clinician_password})
        if r.status_code != 200:
            print("Test clinician login failed; verify the already-provisioned account and smoke credentials.", file=sys.stderr)
            sys.exit(1)
        tok = r.json()
        if not tok.get("access_token") or not tok.get("refresh_token"):
            print("Test clinician login did not return the required tokens.", file=sys.stderr)
            sys.exit(1)
        tokens["clinician"] = {"Authorization": f"Bearer {tok['access_token']}"}
        me = c.get("/api/v1/auth/me", headers=tokens["clinician"])
        if me.status_code != 200 or me.json().get("role") != "clinician":
            print("Smoke credentials must belong to an already-provisioned test clinician.", file=sys.stderr)
            sys.exit(1)

        for i, (key, role) in enumerate(actors, 1):
            phone = phones[key]
            r = c.post("/api/v1/auth/register", json={
                "phone": phone, "email": f"{key}-{pid_os}@test.in", "password": "pass1234",
                "role": role, "preferred_language": "assamese"})
            check(f"POST /auth/register ({role})", r, 201, "id")
            r = c.post("/api/v1/auth/login", json={"phone": phone, "password": "pass1234"})
            tok = check(f"POST /auth/login ({role})", r, 200, "access_token")
            if tok:
                tokens[key] = {"Authorization": f"Bearer {tok['access_token']}",
                               "refresh": tok["refresh_token"]}

        h = tokens["patient"]
        check("GET /auth/me", c.get("/api/v1/auth/me", headers=h), 200, "role")
        # remember the caregiver's user id for roster calls
        me = check("GET /auth/me (caregiver)", c.get(
            "/api/v1/auth/me", headers=tokens["caregiver"]), 200, "id")
        tokens["caregiver"]["uid"] = me["id"]

        r = c.post("/api/v1/auth/refresh", json={"refresh_token": h["refresh"]})
        new = check("POST /auth/refresh", r, 200, "access_token")
        tokens["patient"] = {"Authorization": f"Bearer {new['access_token']}", "refresh": h["refresh"]}
        h = tokens["patient"]
        check("POST /auth/logout", c.post("/api/v1/auth/logout", headers=h), 200)

        # ---------- patient profile ----------
        r = c.post("/api/v1/patients", headers=h, json={
            "name": "Aai Test", "dob": "1948-03-15", "cognitive_baseline": "healthy",
            "region": "assam", "district": "kamrup",
            "routine": {"steps": [{"step_id": "s1", "order": 1, "time": "07:00",
                                   "title_en": "Morning tea", "icon": "tea"}]}})
        body = check("POST /patients", r, 201, "id")
        if not body:
            sys.exit(1)
        patient_id = body["id"]
        check("GET /patients/me", c.get("/api/v1/patients/me", headers=h), 200, "id")

        # DPDP: explicit consent before any health/game/voice storage
        r = c.post("/api/v1/compliance/consent", headers=h, json={
            "patient_id": patient_id, "consent_type": "patient_self", "scope": "all"})
        check("POST /compliance/consent (before health data)", r, 200, "id")

        # caregiver-patient link (family, basic) so the dashboard roster sees this patient
        r = c.post(f"/api/v1/patients/{patient_id}/caregivers", headers=h, json={
            "caregiver_id": tokens["caregiver"]["uid"], "relationship_type": "family",
            "permission_tier": "basic"})
        check("POST /patients/{id}/caregivers (patient owner delegates)", r, 201, "id")

        # ---------- games (patient plays) ----------
        r = c.get("/api/v1/games/content-packs", headers=h)
        packs = check("GET /games/content-packs", r, 200)
        pack_id = packs[0]["id"] if packs else None
        r = c.get(f"/api/v1/games/content-packs/{pack_id}/board?difficulty=1", headers=h)
        check("GET /games/content-packs/{id}/board", r, 200, "cards")

        r = c.post("/api/v1/games/sessions", headers=h, json={
            "game_type": "match_it", "difficulty_level": 1, "content_pack_id": pack_id})
        sess = check("POST /games/sessions", r, 200, "session_id")
        sid = sess["session_id"]
        r = c.post(f"/api/v1/games/sessions/{sid}/actions", headers=h, json={
            "action_type": "card_flip", "action_data": {"card": 1},
            "is_correct": True, "response_time_ms": 1800})
        check("POST /games/sessions/{id}/actions", r, 200, "status")
        check("POST /games/sessions/{id}/complete", c.post(
            f"/api/v1/games/sessions/{sid}/complete", headers=h), 200, "accuracy_pct")

        # caregiver + clinician views (staff role gates)
        ch = tokens["caregiver"]
        clin = tokens["clinician"]
        check("GET /games/patients/{id}/history (clinician, clinical tier)", c.get(
            f"/api/v1/games/patients/{patient_id}/history", headers=clin), 200)
        check("GET /games/patients/{id}/history (family basic denied)", c.get(
            f"/api/v1/games/patients/{patient_id}/history", headers=ch), 403)
        check("GET /games/patients/{id}/routine", c.get(
            f"/api/v1/games/patients/{patient_id}/routine", headers=h), 200, "routine")
        check("GET /games/routine/board", c.get(
            f"/api/v1/games/routine/board?patient_id={patient_id}&difficulty_level=1",
            headers=h), 200, "shuffled_items")
        check("POST /games/difficulty/evaluate (caregiver)", c.post(
            f"/api/v1/games/difficulty/evaluate?patient_id={patient_id}"
            f"&game_type=match_it&current_difficulty=1", headers=ch), 200, "reason")

        # ---------- reminders: caregiver creates schedule, patient acks ----------
        r = c.post("/api/v1/reminders/schedules", headers=ch, json={
            "patient_id": patient_id, "reminder_type": "medicine",
            "cadence": "08:00,14:00,20:00"})
        sched = check("POST /reminders/schedules (caregiver)", r, 200, "id")
        sched_id = sched["id"]
        check("GET /reminders/schedules/{pid}", c.get(
            f"/api/v1/reminders/schedules/{patient_id}", headers=ch), 200)

        r = c.post("/api/v1/reminders/events", headers=ch, json={
            "schedule_id": sched_id, "patient_id": patient_id,
            "scheduled_at": "2026-09-05T08:00:00+05:30"})
        ev = check("POST /reminders/events (caregiver)", r, 200, "id")
        ev_id = ev["id"]
        r = c.post(f"/api/v1/reminders/events/{ev_id}/acknowledge", headers=h,
                   json={"method": "button"})
        check("POST /reminders/events/{id}/acknowledge (patient)", r, 200, "status")
        check("GET /reminders/patients/{pid}/events", c.get(
            f"/api/v1/reminders/patients/{patient_id}/events", headers=h), 200)
        check("POST /reminders/patients/{pid}/evaluate-escalations", c.post(
            f"/api/v1/reminders/patients/{patient_id}/evaluate-escalations", headers=ch), 200)

        # ---------- caregiver dashboard ----------
        check("GET /dashboard/caregivers/{id}/patients (caregiver)", c.get(
            f"/api/v1/dashboard/caregivers/{tokens['caregiver']['uid']}/patients",
            headers=ch), 200)

        # ---------- offline sync: patient pushes batch, clinician inspects queue ----------
        r = c.post("/api/v1/sync", headers=h, json={
            "patient_id": patient_id,
            "items": [{
                "resource_type": "offline_symptom", "operation": "create",
                "resource_id": str(uuid.uuid4()),
                "payload": {"note": "felt a bit tired", "severity": 2,
                            "recorded_at": "2026-09-05T09:00:00+05:30"}}]})
        check("POST /sync (batch)", r, 200, "synced")
        check("GET /sync/pending/{pid} (clinician)", c.get(
            f"/api/v1/sync/pending/{patient_id}", headers=tokens["clinician"]), 200)

        # ---------- companion: clinician manages prompts, patient chats ----------
        check("GET /companion/config (clinician)", c.get(
            "/api/v1/companion/config", headers=tokens["clinician"]), 200)
        r = c.post("/api/v1/companion/config", headers=tokens["clinician"], json={
            "version": "1.1.0", "activate": True,
            "persona_name": "Saathi",
            "system_prompt": ("You are Saathi, a calm and patient companion for an "
                              "elderly user. Use short simple sentences.")})
        if r.status_code == 409:
            # version already exists from a prior run — idempotent, treat as pass
            global PASS
            PASS += 1
            print("  [PASS] POST /companion/config (clinician) — already exists (409, idempotent)")
        else:
            check("POST /companion/config (clinician)", r, 201, "version")
        check("POST /companion/config/1.1.0/activate", c.post(
            "/api/v1/companion/config/1.1.0/activate", headers=tokens["clinician"]),
            200, "version")
        r = c.post("/api/v1/companion/chat/text", headers=h, json={
            "patient_id": patient_id, "message": "Hello", "language": "assamese"})
        check("POST /companion/chat/text", r, 200, "reply_text")

        # ---------- language (mock provider) ----------
        check("GET /language/status", c.get("/api/v1/language/status", headers=h), 200, "provider")
        r = c.post("/api/v1/language/translate", headers=h, json={
            "text": "Good morning", "source_language": "english", "target_language": "assamese"})
        check("POST /language/translate (mock)", r, 200, "translated_text")

        # ---------- RAG (staff ingest/query/answer) ----------
        check("POST /reports/documents/ingest (family basic denied)", c.post(
            "/api/v1/reports/documents/ingest", headers=ch, json={
                "patient_id": patient_id, "file_ref": "rx-basic.pdf", "doc_type": "prescription",
                "extracted_text": "should not ingest"}), 403)
        r = c.post("/api/v1/reports/documents/ingest", headers=clin, json={
            "patient_id": patient_id, "file_ref": "rx-0001.pdf", "doc_type": "prescription",
            "title": "Dosage card",
            "extracted_text": ("Take one tablet of Amlodipine 5 mg every morning. "
                               "Take Metformin 500 mg twice daily with meals. "
                               "If dizziness occurs, contact the clinic. "
                               "Keep blood pressure below 140/90.")})
        doc = check("POST /reports/documents/ingest (clinician)", r, 200, "document_id")
        if doc:
            r = c.post("/api/v1/reports/documents/query", headers=clin, json={
                "patient_id": patient_id, "query": "What is the Amlodipine dosage?", "top_k": 2})
            check("POST /reports/documents/query (clinician)", r, 200, "matches")
            r = c.post("/api/v1/reports/documents/answer", headers=clin, json={
                "patient_id": patient_id,
                "question": "What medicine should be taken in the morning?"})
            check("POST /reports/documents/answer (clinician)", r, 200, "answer")
        check("GET /reports/patients/{pid}/weekly-summary (clinician)", c.get(
            f"/api/v1/reports/patients/{patient_id}/weekly-summary", headers=clin), 200)
        check("GET /compliance/patients/{pid}/export", c.get(
            f"/api/v1/compliance/patients/{patient_id}/export", headers=h), 200, "patient")

        # ---------- DPDP revocation actually blocks subsequent health use ----------
        listed = check("GET /compliance/consent/{pid}", c.get(
            f"/api/v1/compliance/consent/{patient_id}", headers=h), 200)
        consent_id = None
        if isinstance(listed, list) and listed:
            consent_id = listed[0].get("id")
        if consent_id:
            check("POST /compliance/consent/{id}/revoke", c.post(
                f"/api/v1/compliance/consent/{consent_id}/revoke", headers=h), 200)
            check("POST /games/sessions after revoke", c.post(
                "/api/v1/games/sessions", headers=h,
                json={"game_type": "match_it", "difficulty_level": 1}), 403)
            check("POST /companion/chat/text after revoke", c.post(
                "/api/v1/companion/chat/text", headers=h,
                json={"patient_id": patient_id, "message": "hello", "language": "assamese"}), 403)

        print(f"\n===== E2E SMOKE: {PASS} passed, {FAIL} failed =====")
        if FAIL:
            sys.exit(1)
if __name__ == "__main__":
    main()