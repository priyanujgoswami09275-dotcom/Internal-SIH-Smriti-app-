# Caregiver Dashboard → Mobile Port — Design

**Date:** 2026-09-23
**Approach:** A (incremental refactor of the existing mobile caregiver surface)
**Status:** Approved with amendments (see §Amendments)

## Goal

Caregiver (`family_caregiver`), ASHA (`asha_worker`), clinician and `admin`
users who log in on the **phone** see the full caregiver dashboard. Patients
(`patient`) keep the current patient shell untouched, except one static line
(Amendment 2). The web dashboard (`dashboard/`) is **not modified**.

## Constraints (user-imposed)

1. `dashboard/` stays untouched (web app).
2. Reuse `mobile/lib/services/api_service.dart` + `auth_session.dart`
   (single-flight refresh); add missing endpoints there. Do NOT copy
   `dashboard`'s `Api` class.
3. Split dashboard UI into widgets under `mobile/lib/screens/caregiver/`.
   Keep CustomPaint sparklines (no chart dependency).
4. Replace `dart:html` usage with `file_picker` for RAG upload (mobile side).
5. Role routing in `main.dart`: `patient` → patient shell; `family_caregiver`
   → basic tier; `asha_worker`/`clinician` → clinical tier; `admin` → also
   the audit viewer. Server gates stay authoritative; 403 handled gracefully.
6. Single-column, phone-width layout; 48px touch targets; Monad tokens from
   `mobile/lib/theme/monad_theme.dart`.
7. Widget tests per role. `flutter analyze` must pass. Update `PRD.md` and
   `ARCHITECTURE.md` where they say the dashboard is web-only.

## Amendments (user-approved changes to the base design)

1. **Consent-required states.** `documents_card` and
   `risk_screening_section` must show an explicit "health_data consent
   required" state — no silent failures. Source of truth: the server 403s
   with `detail: "Active consent required for scope 'health_data'"`.
   Mobile surfaces that detail text; it does NOT proactively check consent.
2. **Patient shell static line.** Exactly one line added to `PatientHome`:
   > "Your caregiver can add your health documents."
   No other patient-shell changes.
3. **Dev role menu.** `DevRoleMenu` gated behind `kDebugMode` (replacing or
   combining with the existing `--dart-define=DEV_MENU` flag). Roles come
   from the server only (`AuthSession.user.role`); the menu never changes
   role semantics.
4. **Feature branch + incremental extraction.** New branch off
   `fix/app-breakage-wave1-7`; extract one section widget at a time; run
   existing tests after each extraction.
5. **Mocked role tests only.** New role tests mock `ApiService`/HTTP. Never
   run `api_live_test` or `integration_test` against the demo DB.
6. **Doc edits verified against actual files.** Before editing
   PRD/ARCHITECTURE lines, re-read them; only touch lines that claim
   "web-only".
7. **Shrunk-font tests.** Widget tests also run at `textScaleFactor 1.3`
   for the caregiver screens.

Plus standing instruction: audit viewer stays a **card list** (not a table).

## Current state (repo facts)

- `mobile/lib/screens/caregiver_dashboard_screen.dart` — 883-line orchestrator
  already covering: roster loading, patient switcher (ASHA-only), summary,
  alerts + ack, metric tiles, trends (CustomPaint `TrendChart`), compliance
  log, schedules CRUD, documents entry, audit card (honest 403), clinical
  notes + RAG upload push screens, 429 rate-limit banner.
- `mobile/lib/services/api_service.dart` already has: `caregiverPatients`,
  `patientSummary`, `acknowledgeAlert`, `createSchedule`, `deleteSchedule`,
  `auditLogs`, `reminderEvents`, `reminderSchedules`.
- `main.dart` routes: `role == patient` → patient shell; else → dashboard.
- Role enum: `patient, familyCaregiver, ashaWorker, clinician, admin`.
- `DevRoleMenu` exists, currently gated by `--dart-define=DEV_MENU`.

## Gap list (what the port adds)

1. **Risk screening** (absent from mobile): port `RiskIntakeForm` (32
   fields) + `RiskScreeningCard` + `ApiService.submitRiskScreening` →
   `POST /api/v1/patients/{id}/risk-screening`. Clinical tier only; basic
   tier sees the locked note. 403 (`health_data` consent) shown explicitly.
2. **RAG upload real picker**: add `file_picker` to `pubspec.yaml`
   (supersedes the earlier hold); `_pickFile()` selects pdf/txt → bytes →
   `ApiService.uploadDocument` (new endpoint method, authed multipart; the
   existing `buildRagUploadRequest` contract moves behind the service so
   single-flight refresh applies).
3. **Decomposition**: split the 883-line screen into section widgets under
   `mobile/lib/screens/caregiver/` (one section at a time — Amendment 4).
4. **Role routing**: explicit tier awareness in `main.dart`/`HomeShell` —
   `admin` additionally exposes the audit-viewer entry; tiers otherwise
   server-driven (`summary['view']`), client renders accordingly.
5. **Per-role widget tests** (mocked) + textScaleFactor 1.3 variants.
6. **Docs**: `PRD.md` L80 area + `ARCHITECTURE.md` §26/§67 (web-only claims).

## Target structure

```
mobile/lib/screens/caregiver/
  caregiver_dashboard_screen.dart   # orchestrator: loads data, composes sections
  audit_viewer_screen.dart          # pushed card-list viewer (admin entry)
  sections/
    patient_switcher.dart           # ASHA-only dropdown
    alerts_card.dart                # flags + active alerts + ack
    metrics_tiles.dart              # accuracy / compliance / speed
    trends_section.dart             # CustomPaint sparklines (reuses widgets/trend_chart.dart)
    compliance_log.dart             # today\'s reminder events
    schedules_card.dart             # schedule list + add/delete sheet
    documents_card.dart             # RAG entry + consent-required empty state
    risk_screening_section.dart     # card + intake button / locked basic note
    risk_intake_form.dart           # 32-field dialog form
    risk_screening_card.dart        # last result display
```

The orchestrator remains the state owner (patients, summary, events,
schedules) and passes data + callbacks to pure section widgets.

## Components & contracts

**`ApiService` additions** (no dashboard client copied):

```dart
Future<Map<String, dynamic>> submitRiskScreening({
  required String patientId,
  required Map<String, dynamic> payload,
});

Future<dynamic> uploadDocument({
  required String patientId,
  required Uint8List bytes,
  required String filename,
  String docType = 'prescription',
  String? title,
});
```

`uploadDocument` routes through the service's authed `_send` so the
single-flight refresh covers it. The `patient_id`-as-query+field contract
(already proven in `rag_upload_test`) is preserved.

**Consent & tier surfacing (Amendment 1):**
- `documents_card`: entry button only when a patient is selected. The pushed
  upload screen returns its terminal status via `Navigator.pop` result;
  when it returned the 403 `health_data` detail, the card switches into a
  persistent tinted state — "This patient hasn't granted health_data
  consent; documents can't be uploaded until they do" — instead of merely
  the static helper text. Server-side `formatRagUploadFailure` already
  carries the consent detail for 403s; nothing is swallowed silently.
- `risk_screening_section`: clinical tier shows the intake button; 403 on
  submit renders the consent-required state inline on the section; basic
  tier keeps the existing locked note. No silent swallow — the error text
  includes the server's detail.

**Role routing (`main.dart` `HomeShell`):**

```dart
switch (user.role) {
  patient         → PatientHome (unchanged, + static line)
  family_caregiver→ CaregiverDashboardScreen (basic)
  ashaWorker      → CaregiverDashboardScreen (clinical)
  clinician       → CaregiverDashboardScreen (clinical)
  admin           → CaregiverDashboardScreen (clinical + audit entry visible)
}
```

Role comes from `AuthSession.instance.user` (server-issued). The server
remains authoritative — client only pre-hides entry points; every section
still renders honest 403/`view=basic` states.

**Audit viewer (admin):** an `Icons.fact_check` app-bar action visible only
when `role == Role.admin` pushes `AuditViewerScreen` — a card list (per
user instruction) of `GET /compliance/audit-logs` entries, reusing the
honest-403 text pattern from the existing `_auditCard`. (The inline
`_auditCard` in the dashboard body is replaced by this pushed screen to
avoid a per-render FutureBuilder fetch for non-admins.)

**Dev menu (Amendment 3):** `DevRoleMenu` render gate becomes
`kDebugMode && DevRoleMenu.enabled`; drawer attachment in
`main.dart`/`caregiver_dashboard_screen.dart` uses the same gate so release
builds drop it entirely (tree-shaken out).

**Layout/tokens:** single-column `ListView` at phone width; interactive
controls ≥48px (existing `MonadPillButton` already expanded; icon buttons
get `constraints: BoxConstraints(minWidth: 48, minHeight: 48)` where
smaller); Monad tokens only (`Monad.*`), no chart dependency — sparklines
stay CustomPaint.

## Data flow

Roster → select patient → summary (+events, schedules) as today; new:
screening POST marks a local `_riskScreeningResult` feeding
`risk_screening_card`. Documents upload completes then the pushed screen
pops back (current behavior). Nothing new joins the offline outbox —
dashboard is live-only except reminder ack (unchanged).

## Error handling

- 429 → existing rate-limit banner.
- 403 with `health_data` detail → explicit consent-required copy
  (Amendment 1) on documents + screening sections.
- 403 admin-only (audit) — non-admins: no entry; direct navigator push
  without role → "Audit trail is admin-only" card state.
- Network/API failure → section-level fallback text (current pattern).

## Testing

All new tests mock `ApiService`/HTTP (Amendment 5 — never
`api_live_test`/`integration_test` against the demo DB):

| Test file | Coverage |
|---|---|
| `caregiver_role_routing_test.dart` | HomeShell: patient→shell; family/asha/clinician/admin→dashboard; admin-only audit entry |
| `caregiver_tiers_test.dart` | basic tier: locked trends + no screening button; clinical: sections visible; switcher ASHA-only |
| `risk_screening_test.dart` | intake form renders + submits payload; 403 consent card; result card display |
| `rag_upload_picker_test.dart` | file_picker path → uploadDocument payload; 403 consent detail surfaced |
| textScaleFactor 1.3 | each caregiver screen re-pumped at 1.3 scale, asserts key copy present |

Existing `rag_upload_test.dart` and `schedule_delete_contract_test.dart`
MUST keep passing — imports updated to new section paths after each
extraction (Amendment 4: run `flutter test` per extraction).

Gates: `flutter analyze` (no new issues), `flutter test` all green.

## Docs

- `PRD.md` — Caregiver Dashboard table: "Flutter Web" → "Flutter Web +
  mobile (role-routed)" (verified actual text: line 80 "Flutter Web: JWT
  login, patient roster, 7-day metric tiles").
- `ARCHITECTURE.md` — architecture diagram block ("Caregiver Dashboard │
  Flutter Web") and the "Caregiver Dashboard" section ("Framework: Flutter
  Web") — updated to record the mobile port with role routing, and the new
  `mobile/lib/screens/caregiver/` structure + `file_picker` dep.

## Out of scope

- Any change to `dashboard/` (stays as web app).
- Clinical notes rework (already on mobile).
- Offline/dashboard caching (live-only by design).
- Risk-screening GET/history (server has none — session-result card only).
