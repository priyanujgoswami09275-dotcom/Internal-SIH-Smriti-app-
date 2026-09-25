# PRD — Smriti: Cognitive Gaming & Memory Assistance Platform

**Problem Statement:** SIH26003 · Ministry of Development of North Eastern Region (MDoNER) · Smart India Hackathon 2026 · Status: experimental prototype, built and tested · Reconciled: 2026-09-25

---

## 1. Problem & Opportunity

The North Eastern Region (NER) of India faces a growing burden of age-related cognitive disorders among its elderly population. Remote and rural families struggle to access specialized neurological care and cognitive therapy due to limited healthcare infrastructure and geographical barriers. SIH26003 (MDoNER) calls for a software solution that addresses this gap.

**Why cognitive training?** Large longitudinal randomized trials have demonstrated that structured cognitive interventions can reduce dementia incidence in at-risk elderly populations. The ACTIVE study (Advanced Cognitive Training for Independent and Vital Elderly) showed that speed-of-processing training — a form of cognitive stimulation — improved cognitive outcomes in older adults, and the FINGER trial demonstrated that a multidomain lifestyle intervention (diet, exercise, cognitive training, and vascular risk management) reduced cognitive decline. Meta-analytic evidence supports video-game-based interventions improving cognition in Mild Cognitive Impairment (MCI) patients. These are **evidence-based intervention categories** — they are not claims that Smriti itself has been clinically validated or that it produces specific health outcomes. Smriti is an experimental research prototype; its risk-screening model is not clinically validated and is not a medical device.

**Why NER specifically?** The region's linguistic diversity (10+ major languages), intermittent connectivity in rural areas, and limited specialist healthcare access favor a multilingual, offline-capable, voice-guided platform. Cultural familiarity in content (local festivals, flora, fauna, attire) supports engagement where generic interfaces fail.

---

## 2. Target Users

**Patient (elderly, MCI or at-risk).** Uses the app daily to play cognitive games, receive reminders, and interact with the voice companion. The interface prioritizes large text (body floor 20px), high-contrast colors, voice-guided navigation, and culturally familiar content. The current grant workflow requires active patient-self consent; a verified guardian/joint workflow is not implemented in this round.

**Family caregiver.** Monitors a loved one's activity, game performance trends, and reminder compliance from a remote dashboard. Receives alerts for missed routines or cognitive decline signals. Has basic-tier access by default; clinical detail requires explicit permission tiers.

**ASHA / health worker.** Manages multiple patients across villages. Sees clinical summaries, RAG-sourced medical documents (with consent), and aggregated alerts. Acts as the field presence for follow-up care.

**Clinician.** Reviews raw scores, health data, and screening outputs for patients under their care. Has the highest permission tier and access to clinical detail, including document RAG.

---

## 3. User Stories

**As a patient**, I want to play memory-matching and sequencing games in my preferred NER language, so that I stay cognitively engaged with culturally familiar content even without internet.

**As a patient**, I want voice-guided reminders for medicine and meals, so that I do not miss doses even if I cannot read a screen.

**As a patient**, I can talk to a friendly voice companion in my language, so that navigation and emotional check-ins do not require reading or typing.

**As a family caregiver**, I can see my parent's weekly game accuracy and reminder compliance on a dashboard, so that I can spot concerning trends without being present.

**As an ASHA worker**, I can view clinical summaries and medical documents for several patients, so that I can prioritize follow-up visits during field rounds.

**As a clinician**, I can run a consented preliminary risk screening and review the result alongside the patient's game data, so that I can triage cognitive concerns early.

---

## 4. Functional Requirements

### Cognitive Games
| Feature | Status |
|---|---|
| Match It (memory card game, NER-themed content packs) | Built + tested |
| Daily Routine Sequencing (config-driven steps, 3 levels) | Built + tested |
| Number Recall — digit sequences at 3/4/6 digits (word mode is not implemented) | Built + tested |
| Odd-One-Out (semantic-category board, seeded generator, session-bound scoring) | Built + tested |
| Server-authoritative rule difficulty: 3 consecutive >85% may raise, 2 consecutive <50% may lower; `game_level_config` controls board parameters | Built + tested |
| Offline-capable play with account-scoped completed-round replay | Built + tested; exact in-progress round resume after app death is not implemented |

*Known limitation: level-3 Odd-One-Out boards are currently festivals-pack-only (the sole group with ≥5 unambiguous items); broader content authoring is pending.*

### Reminders
| Feature | Status |
|---|---|
| Scheduled voice-guided reminders (medicine, water, food, exercise) | Built + tested |
| Cadence grammar: optional `daily`/`everyday`/`every day` prefix plus one or more `HH:MM` values separated by comma/semicolon; legacy `HH:MM AM|PM Daily` accepted | Built + tested |
| Offline local notifications | Built + tested |
| Acknowledgment logging and sync | Built + tested |
| Notification delivery state | `not_configured` + zero confirmed deliveries by default; never represented as sent |
| Escalation: 10-min reprompt → 3 missed in 7 days → AlertFlag + family/ASHA fan-out | Built + tested |
| Spoken reminders with cached server TTS, ack-screen playback | Built + tested |

### Voice Companion
| Feature | Status |
|---|---|
| 10-language picker with operation-specific provider gating; Garo always "not yet available" | Built + tested |
| Server-side ASR → LLM → TTS provider pipeline (Sarvam → AI4Bharat → Bhashini → mock) | Contract-tested; live calls require operator credentials |
| Mic capture + reply playback on-device | Software path built/tested; physical-device validation outstanding |
| Cached TTS playback | Built + tested; cache is a performance aid |
| Deterministic mock speech and canned LLM reply when no provider key is configured | Built + tested; default shipped example is simulated, not live |

### Caregiver Dashboard
| Feature | Status |
|---|---|
| Multi-file Flutter Web + mobile role-routed port: JWT session, patient roster, permission-tier-driven controls | Built + tested |
| 14-day accuracy + response-time trend sparklines (pure `CustomPaint`) | Built + tested |
| `health_data` consent preflight for risk screening and document upload | Built + tested |
| Active-alert acknowledgement, clinical insight, and reminder-schedule add/remove | Built + tested |
| Admin audit viewer with 50-row offset pagination | Built + tested |
| Release API URL must be supplied explicitly with `--dart-define=API_BASE_URL` | Built + tested |

### Document / RAG Support
| Feature | Status |
|---|---|
| Selectable-text PDF/text upload + chunking + cited answers | Built + tested |
| Embedding provider/model/dimension provenance; mismatches refuse retrieval pending reindex | Built + tested |
| Fernet encryption for document source text and new chunk text | Built + tested |
| Patient-scoped reindex command; backfills provenance and converts legacy plaintext chunk rows to ciphertext with a write-audit row | Built + tested |
| Scanned/image-only PDF and OCR | Not in this build; rejected before persistence with paste-text/text-PDF guidance |
| Extractive fallback without LLM keys | Built + tested |
| Clinical access + `health_data` consent gates | Built + tested |

### Risk Screening (Phase A — ML track)
| Feature | Status |
|---|---|
| `POST /patients/{id}/risk-screening` with `health_data` consent + clinical access | Built + tested |
| Persistence + audit logging (PostgreSQL upsert) | Built + tested |
| **Experimental, not clinically validated**; isolated from gameplay decisions | Built + tested, fully functional — experimental and not clinically validated as a screening tool |

### Compliance
| Feature | Status |
|---|---|
| Patient-self consent capture with scope gates (`game_data`, `health_data`, `voice_companion`); guardian/joint enum values are not accepted by the current grant policy | Built + tested for patient-self scope |
| Purpose limitation enforced at route level | Built + tested |
| Fernet at-rest encryption (symptom notes, medical-document source text, document chunks) | Built + tested |
| Broad read and representative write audit rows; best-effort and fail-closed paths tested | Built + tested; database-level immutability is not enforced |
| Data retention + deletion jobs (DPDP Act 2023) | Built + tested |
| Fail-closed data export (`GET /compliance/patients/{id}/export`) | Built + tested |
| JWT access + single-use refresh rotation | Built + tested |
| API-only app-layer RBAC (patient / family_caregiver / asha_worker / clinician / admin) | Built + tested |

---

## 5. Non-Functional Requirements

### Accessibility
- **Text-size floor:** patient-facing strings use 20px minimum (body-lg); 14–16px reserved for metadata/captions only. Design tokens enforce this in `DESIGN.md`.
- **Touch targets:** pill buttons are 48px minimum height; interactive elements use `WidgetStatePropertyAll(Size(64, 48))`.
- **Color is never the sole conveyer:** card-face tints always pair with a distinct illustration + text label; reminder types always conveyed by icon + label + tint together. Tints at ≤25% opacity over Parchment exceed WCAG AA 10:1 contrast.
- **Typography:** ABC Diatype Mono for all functional UI; Untitled Serif at weight 400 for headings (never bold). Warm Parchment (#f6f3f1) canvas, never pure white.

### Offline-Capable Client
- Match It, Routine Sequencing, and Number Recall can start with bundled/local
  data; Odd-One-Out requires a compatible cached public board.
- Completed offline sessions/actions and reminder acknowledgments enter a drift
  SQLite outbox. Rows are patient- and account-scoped; replay selects only the
  active account, failed rows stay pending, and synced backend rows are purged
  after seven days.
- Server level config and public Odd-One-Out board snapshots persist across app
  restarts. Reminder audio is cached by text + language in temporary files.
- Local reminder notifications fire without internet.
- **An in-progress game round is not resumable after app death**: board, moves,
  timers, and action buffer are widget memory. Completed outbox work is durable.
- Document uploads and clinical reads fail visibly offline; they are not queued.
- Backend `/sync` materializes eligible operations idempotently.

### Multilingual and Speech Scope
- **Product list (10):** assamese, bengali, hindi, english, mizo, manipuri,
  khasi, bodo, nepali, garo
- `manipuri` is canonical; `meitei` is accepted as its alias. `garo` has no
  provider code and is always disabled.
- NER-relevant capability maps:
  - Sarvam ASR/NMT: Assamese, Bengali, Hindi, English, Manipuri/Meitei, Bodo,
    Nepali; TTS: Bengali, Hindi, English.
  - AI4Bharat ASR/NMT/TTS: Assamese, Bengali, Bodo, Manipuri/Meitei, Nepali,
    Hindi, English. The client exists, but the default HF router does not serve
    these models; a dedicated endpoint is required.
  - Bhashini request path ASR/NMT/TTS: Assamese, Bengali, Hindi, English,
    Manipuri/Meitei, Bodo, Nepali, Mizo, Khasi.
  - Mock: deterministic simulation for advertised picker languages.
- The shipped example has no provider credentials. With no operator-supplied
  key, `auto` selects mock and `/language/status` prevents the UI from presenting
  simulated operations as live capability.

### DPDP Act 2023 Compliance Posture
- **Consent:** patient-self grant and active `game_data`, `health_data`, or
  `voice_companion` scope gates. Guardian/joint enum values exist but are not an
  implemented grant workflow.
- **Audit:** broad read plus representative write rows. Most helpers are
  best-effort; consent grant/revoke, document ingest/reindex, and export are
  fail-closed. Retention excludes audit rows, but **database-level immutability is
  not enforced**.
- **Encryption:** Fernet protects symptom notes, medical-document source text,
  and document chunks; bcrypt protects password hashes.
- **Retention:** game sessions 2 years, symptom logs 1 year, reminder events ~6
  months, medical documents 5 years, synced sync rows 7 days; revoked consents
  and linked screening rows hard-delete after 30 days.
- **Access:** clients use REST/JWT only. There is no direct Supabase/Firebase
  table access. Direct client access would require a new RLS/JWT/tenant threat
  model and security tests before it could be enabled.

---

## 6. Explicit Out-of-Scope (This Round)

| Feature | Rationale |
|---|---|
| Multiplayer / social gaming | Deferred — requires consensus protocols, conflict resolution, and real-time sync beyond MVP scope |
| Family media / reminiscence upload | Deferred — storage costs, privacy complexity, and no validated therapeutic protocol for this round |
| Wandering / GPS safety hardware | Deferred — requires dedicated hardware integration and regulatory clearance outside software scope |
| Village-level offline hub | Deferred — needs physical infrastructure (local server/hotspot) and community coordination beyond this project |
| ABHA / ABDM integration | Deferred — requires government API integration, consent architecture changes, and regulatory review |
| IVR / feature-phone fallback | Deferred — requires telephony infrastructure and would fragment the UX; app-first strategy is deliberate for the target demographic |
| In-app OCR / scan-to-text capture | Not required for the current PDF/text upload scope; scanned/image-only PDFs are rejected with paste-text/text-PDF guidance. A scanner plus on-device OCR would need separate approval, native permissions, and new dependencies. |

---

## Disclaimers

**Smriti is an experimental research prototype.** The risk-screening model is not clinically validated and is not a medical device. The adaptive difficulty model runs in shadow mode only; rule-based logic remains the sole authority for real difficulty decisions. No claims are made about Smriti's clinical outcomes, diagnostic capability, or ability to prevent, treat, or cure dementia or any other condition. Cognitive training interventions have evidence-based potential in research contexts; this prototype does not claim to deliver those outcomes.
