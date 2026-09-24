# PRD — Smriti: Cognitive Gaming & Memory Assistance Platform

**Problem Statement:** SIH26003 · Ministry of Development of North Eastern Region (MDoNER) · Smart India Hackathon 2026 · Status: built and tested · Date: 2026-09-21

---

## 1. Problem & Opportunity

The North Eastern Region (NER) of India faces a growing burden of age-related cognitive disorders among its elderly population. Remote and rural families struggle to access specialized neurological care and cognitive therapy due to limited healthcare infrastructure and geographical barriers. SIH26003 (MDoNER) calls for a software solution that addresses this gap.

**Why cognitive training?** Large longitudinal randomized trials have demonstrated that structured cognitive interventions can reduce dementia incidence in at-risk elderly populations. The ACTIVE study (Advanced Cognitive Training for Independent and Vital Elderly) showed that speed-of-processing training — a form of cognitive stimulation — improved cognitive outcomes in older adults, and the FINGER trial demonstrated that a multidomain lifestyle intervention (diet, exercise, cognitive training, and vascular risk management) reduced cognitive decline. Meta-analytic evidence supports video-game-based interventions improving cognition in Mild Cognitive Impairment (MCI) patients. These are **evidence-based intervention categories** — they are not claims that Smriti itself has been clinically validated or that it produces specific health outcomes. Smriti is an experimental research prototype; its risk-screening model is not clinically validated and is not a medical device.

**Why NER specifically?** The region's linguistic diversity (10+ major languages), intermittent connectivity in rural areas, and limited specialist healthcare access make a multilingual, offline-first, voice-guided platform uniquely suited. Cultural familiarity in content (local festivals, flora, fauna, attire) drives engagement where generic interfaces fail.

---

## 2. Target Users

**Patient (elderly, MCI or at-risk).** Uses the app daily to play cognitive games, receive reminders, and interact with the voice companion. The interface prioritizes large text (body floor 20px), high-contrast colors, voice-guided navigation, and culturally familiar content. For patients who cannot consent, a guardian grants consent on their behalf.

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
| Number/Word Recall (config-driven board, scoring) | Built + tested |
| Odd-One-Out (semantic-category board, seeded generator, session-bound scoring) | Built + tested, merged to main |
| Adaptive difficulty (85% bump / 50% drop, 3-session rule, `game_level_config` as source of truth) | Built + tested |
| Offline play with sync on reconnect | Built + tested |

*Known limitation: level-3 Odd-One-Out boards are currently festivals-pack-only (the sole group with ≥5 unambiguous items); broader content authoring is pending.*

### Reminders
| Feature | Status |
|---|---|
| Scheduled voice-guided reminders (medicine, water, food, exercise) | Built + tested |
| Offline local notifications | Built + tested |
| Acknowledgment logging and sync | Built + tested |
| Escalation: 10-min reprompt → 3 missed in 7 days → AlertFlag + family/ASHA fan-out | Built + tested |
| Spoken reminders with cached server TTS, ack-screen playback | Built + tested |

### Voice Companion
| Feature | Status |
|---|---|
| 10-language picker (provider-gated; garo always "not yet available") | Built + tested |
| Server-side ASR → LLM → TTS pipeline (Sarvam primary, Bhashini fallback; AI4Bharat implemented but non-functional pending a dedicated HF endpoint) | Built + tested |
| Mic capture + reply playback on-device | Built + tested (emulator/macOS only; physical-device validation outstanding) |
| Cached TTS playback | Built + tested |
| Canned-reply fallback when no API key | Built + tested |

### Caregiver Dashboard
| Feature | Status |
|---|---|
| Flutter Web + mobile (role-routed: family/ASHA/clinician/admin): JWT login, patient roster, 7-day metric tiles | Built + tested |
| 14-day accuracy + response-time trend sparklines (pure CustomPaint) | Built + tested |
| Active-alerts acknowledge + clinical-flags insight | Built + tested |
| Reminder-schedule editing (list/add/delete) | Built + tested |
| Admin audit-trail viewer | Built + tested |

### Document / RAG Support
| Feature | Status |
|---|---|
| PDF/text upload + chunking + stable embeddings + cited answers | Built + tested |
| Extractive fallback without LLM keys | Built + tested |
| Clinical access gated by `ensure_clinical_access` | Built + tested |

### Risk Screening (Phase A — ML track)
| Feature | Status |
|---|---|
| `POST /patients/{id}/risk-screening` with `health_data` consent + clinical access | Built + tested |
| Persistence + audit logging (PostgreSQL upsert) | Built + tested |
| **Experimental, not clinically validated**; isolated from gameplay decisions | Built + tested, fully functional — experimental and not clinically validated as a screening tool |

### Compliance
| Feature | Status |
|---|---|
| Consent capture with scope gates (`game_data`, `health_data`, `voice_companion`) | Built + tested |
| Purpose limitation enforced at route level | Built + tested |
| Fernet at-rest encryption (symptom notes, medical document text) | Built + tested |
| Audit logging on all patient-data access | Built + tested |
| Data retention + deletion jobs (DPDP Act 2023) | Built + tested |
| Data export (`GET /compliance/patients/{id}/export`) | Built + tested |
| JWT access + single-use refresh rotation | Built + tested |
| Role-based access control (patient / family_caregiver / asha_worker / clinician / admin) | Built + tested |

---

## 5. Non-Functional Requirements

### Accessibility
- **Text-size floor:** patient-facing strings use 20px minimum (body-lg); 14–16px reserved for metadata/captions only. Design tokens enforce this in `DESIGN.md`.
- **Touch targets:** pill buttons are 48px minimum height; interactive elements use `WidgetStatePropertyAll(Size(64, 48))`.
- **Color is never the sole conveyer:** card-face tints always pair with a distinct illustration + text label; reminder types always conveyed by icon + label + tint together. Tints at ≤25% opacity over Parchment exceed WCAG AA 10:1 contrast.
- **Typography:** ABC Diatype Mono for all functional UI; Untitled Serif at weight 400 for headings (never bold). Warm Parchment (#f6f3f1) canvas, never pure white.

### Offline-First
- Games fully playable offline; drift SQLite stores GameSession, GameAction, ReminderEvent, SyncQueue
- `OfflineSyncService` replays game sessions and drains the outbox on reconnect (30s poll)
- Local notifications fire without internet; sync queue retained 7 days
- Backend `/sync` accepts batched offline events; consumer job materializes domain rows idempotently

### Multilingual Scope
- **Exact current list (10):** assamese, bengali, hindi, english, mizo, manipuri, khasi, bodo, nepali, garo
- `manipuri` is the canonical request key; `meitei` accepted as alias everywhere
- `garo` has no provider code on any backend; always renders as "not yet available"
- Provider chain gating: Sarvam (broadest), Bhashini (fallback); AI4Bharat implemented but currently non-functional pending a dedicated Hugging Face Inference Endpoint (models not served on serverless platform)

### DPDP Act 2023 Compliance Posture
- **Consent scopes:** `game_data`, `health_data`, `voice_companion`; consent types: `patient_self`, `guardian`, `joint`
- **Audit logging:** immutable log of user_id, action, resource_type, resource_id, timestamp, ip
- **Encryption:** Fernet field encryption (key SHA-256-derived from `ENCRYPTION_KEY`) on `SymptomLog.notes` and `MedicalDocument.extracted_text`; bcrypt for password hashes
- **Retention:** game sessions 2 years, symptom logs 1 year, reminder events 6 months, medical documents 5 years, sync queue 7 days; revoked consents hard-deleted after 30-day grace period
- **Tested:** `test_phase11_gates.py`, `test_phase12_gates.py`

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

---

## Disclaimers

**Smriti is an experimental research prototype.** The risk-screening model is not clinically validated and is not a medical device. The adaptive difficulty model runs in shadow mode only; rule-based logic remains the sole authority for real difficulty decisions. No claims are made about Smriti's clinical outcomes, diagnostic capability, or ability to prevent, treat, or cure dementia or any other condition. Cognitive training interventions have evidence-based potential in research contexts; this prototype does not claim to deliver those outcomes.
