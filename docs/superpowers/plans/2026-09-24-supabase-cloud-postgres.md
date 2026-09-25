# Supabase Cloud PostgreSQL Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the FastAPI backend against a persistent Supabase PostgreSQL database via env-only `DATABASE_URL`, without changing app architecture or touching the local demo DB.

**Architecture:** Pydantic settings load root `.env`; SQLAlchemy async engine keeps `options=-c timezone=UTC`; Alembic reads process env `DATABASE_URL` (with `%` escaped for configparser). Flutter continues to talk only to the HTTP API.

**Tech Stack:** FastAPI, SQLAlchemy async + psycopg3, Alembic, Supabase shared pooler (session mode), Flutter mobile/dashboard.

**Spec:** User task list 2026-09-24 (inspect → env config → verify cloud → tests → report). Local demo `localhost:5432/eldercare` is read-only/untouched.

## Global Constraints

- Never print or commit real DB credentials; only gitignored root `.env`.
- Never DROP/reset/reseed/modify `localhost:5432/eldercare`.
- Before any DB-mutating command: print target host/db; abort if localhost demo.
- Preserve naive-UTC writes + `iso_utc()` serialization.
- Preserve `options=-c timezone=UTC` on app engine.
- Adaptive success remains shadow-only; risk screening experimental with RBAC/consent/audit.
- Rules remain sole difficulty authority.
- No ML model changes.

---

### Task 1: Confirm configuration (inspect-only)

**Files:** Read `backend/app/config.py`, `backend/app/database.py`, `backend/alembic/env.py`, `backend/alembic.ini`, `.env.example`, `.env` (redact password).

**Findings (already verified):**
- `DATABASE_URL` via pydantic `env_file=(repo/.env, backend/.env)` — `config.py:10-11,145-149,186`
- Engine UTC: `database.py:9-19` when URL starts with `postgresql`
- Alembic: `os.getenv("DATABASE_URL")` + `%` → `%%` — `alembic/env.py:20-23`
- Head: `0010_odd_one_out` (chain 0001→0010)
- No runtime code requires DB name `eldercare` (CI/docs only); app default is `elder_care`
- Flutter has no DB credentials (API_BASE_URL only)

- [x] Step 1: Print redacted target; confirm not localhost demo

### Task 2: Env-only config + `.env.example` placeholder

**Files:** Modify `.env.example` only if placeholder incomplete; live credentials stay in root `.env`.

- [x] Step 1: Ensure `.env.example` has `DATABASE_URL=postgresql+psycopg://USER:PASSWORD@HOST:PORT/DATABASE?sslmode=require` shape without secrets
- [x] Step 2: Confirm UTC connect_args and alembic `%` escape unchanged

### Task 3: Alembic on cloud only after URL confirm

**Files:** none (command)

- [x] Step 1: Print target; assert Supabase host
- [x] Step 2: `DATABASE_URL=... python -m alembic upgrade head` → `0010_odd_one_out`, 21 tables

### Task 4: Live API verification on cloud

- [x] Step 1: Backend health + DB round-trip
- [x] Step 2: Create patient + complete game session
- [x] Step 3: Verify row in cloud PostgreSQL
- [x] Step 4: GET history/stats
- [x] Step 5: Adaptive shadow after enough sessions
- [x] Step 6: Risk screening POST/GET

### Task 5: Test suites

- [x] Step 1: `cd backend && python -m pytest app/tests tests -q` → 518 passed, 7 skipped
- [x] Step 2: mobile + dashboard `flutter analyze` + `flutter test` → mobile 108 passed/5 skipped; dashboard 15 passed; no analyze errors

### Task 6: Report

- [x] Step 1: Files changed, config, migrations, connection/session/ML/risk results, remote deploy steps for Flutter
