# Retention deletion audit — design note (option 1: dedicated system user)

**Date:** 2026-09-25
**Status:** design only — no code, no migration, no database change. Demo jobs are
disabled (`ENABLE_BACKGROUND_JOBS=false` in the test/demo config) and the demo
database must stay untouched, so nothing here is applied yet.
**Scope:** `backend/app/services/retention_service.py` (`run_maintenance`), invoked
from `backend/app/jobs.py:120-124` (scheduled) and `backend/app/jobs.py:218-219`
(manual trigger).

## The gap

`RetentionService.run_maintenance` hard-deletes patient data — game sessions,
symptom logs, reminder events, document chunks and documents, sync queue rows,
risk screenings, and grace-expired consents — then commits, **without writing any
`AuditLog` row**. DPDP-wise, bulk deletion of health data is currently the least
audited write in the platform.

The blocker is structural, not an oversight in the service:

- `AuditLog.user_id` is a **non-nullable foreign key** to `users.id`
  (`backend/app/models/compliance.py:47`).
- `run_maintenance(db, now)` receives **no actor**, and neither job caller has an
  authenticated user (the scheduler has no session; the manual trigger runs from
  the job runner).
- There is **no durable system user** in the schema or seed data to attribute the
  deletion to.
- `AuditActionEnum.DELETE` **does** exist (`backend/app/models/compliance.py:38-42`),
  so the action semantics are already available; the blocker is purely the actor.

A previous attempt deliberately stopped here rather than invent a user id or
commit a permanently failing test.

## Option 1 (recommended): a dedicated system actor

Create one inactive `User` row that represents the platform itself, and require
every actor-less maintenance path to attribute its writes to it.

### Shape

- **New user** with a fixed, documented identity — e.g. phone `+910000000000`
  (an obviously non-dialable reserved number), `role = admin` (so it satisfies
  any existing role gate if one is ever applied), `is_active = False`.
- **Frozen credentials:** random unusable `password_hash`, no `email`, and
  `is_active=False` so the login endpoint can never authenticate it. Add a
  defensive assertion in the auth path (or a startup check) that this account is
  rejected even if the flag is ever flipped.
- **Stable id:** the row is provisioned once and its UUID is published as a
  setting (e.g. `SYSTEM_ACTOR_USER_ID`). Code reads the setting; it never
  hardcodes a UUID.
- **Bootstrap:** a small idempotent provisioning step (startup hook or a
  management command) that creates the row if missing. It must be a no-op when
  the setting already points at an existing, inactive user.

### Using it

- `run_maintenance` gains an optional `actor_id` that defaults to the configured
  system actor. The job passes nothing; manual triggers may pass the initiating
  operator's id for a more precise trail.
- After the deletions commit, write **one audit row per run** — not per deleted
  row, which would be unbounded:
  - `action = "delete"` (not `"write"`),
  - `resource_type = "retention_run"`,
  - `resource_id = ` a fresh UUID for the run,
  - `details` = per-table deletion counts only, e.g.
    `{"game_sessions": 128, "symptom_logs": 12, "medical_documents": 3}`.
    **No patient identifiers, no titles, no filenames, no clinical text** — this
    matches the rule every other audit call already follows.
- The audit must be **fail-closed** like document ingestion: a retention run
  that cannot be audited should not silently delete. Practical shape: write the
  run-audit row in the *same transaction* as the deletions, so a failure rolls
  the whole maintenance pass back.

### Testing (no demo database)

- Unit: with a stubbed actor, `run_maintenance` deletes the expected rows **and**
  writes exactly one `action="delete"` audit row with the right counts and no
  PHI in `details` (assert the details key set).
- Fail-closed: force the audit insert to raise and assert **no** rows were
  deleted and no audit row persisted (mirrors
  `test_ingest_is_fail_closed_when_the_audit_cannot_be_written`).
- Bootstrap: provisioning is idempotent — running it twice yields one row and the
  same UUID; the account is inactive and cannot log in.
- Mutation proof: no-op the audit row creation and confirm the delete-audit test
  fails; move the audit after the commit and confirm the fail-closed test fails.

## Alternatives considered

2. **Pass an actor for manual runs only** — accurate for operator-triggered runs
   but leaves the *scheduled* path (the common case) unaudited. Rejected: it
   fixes the easy half of the problem.
3. **Nullable or service-principal actors** — the most expressive long-term model
   (a `system_actors` table, or a nullable `user_id` plus an actor-type column),
   but it needs an Alembic migration on `audit_logs` and changes every audit
   query. Worth revisiting if more than one actor-less job appears.

## Rollout notes

- No demo-database change: the system user is provisioned at startup, not seeded
  into any committed database, and the demo job runner stays disabled.
- Provisioning runs in the same startup path as the existing table creation, so
  a fresh test database gets it automatically.
- If the setting is missing, maintenance should fail loudly (log at error level)
  and skip the run rather than delete unaudited.

## Open questions for the reviewer

- Should the system actor be `role=admin`, or a distinct role that cannot pass any
  API gate even if credentials leaked? The latter is safer but needs a new enum
  value and role-gate review.
- Per-run single row vs. per-table rows: single row keeps the audit table small;
  per-table rows are easier to query for a specific compliance question.
- Retention cadence: should `details` also carry the cutoff timestamp used, so a
  later reader can reconstruct exactly what "old" meant for that run?
