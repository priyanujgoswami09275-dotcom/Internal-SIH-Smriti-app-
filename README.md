# Smriti — AI-Powered Cognitive Gaming and Memory Assistance Platform

**Empowering elderly dementia patients in the North Eastern Region through adaptive cognitive care.**

Smriti — Reviving Memories, Restoring Smiles.

---

## 🧠 About the Project

The North Eastern Region (NER) is witnessing a gradual rise in age-related cognitive disorders such as dementia and memory loss among the elderly population. Many families in remote and rural areas face challenges accessing specialized neurological care and cognitive therapy due to limited healthcare infrastructure and geographical barriers.

**Smriti** is an AI-powered cognitive gaming and memory assistance platform built specifically for elderly dementia patients in NER. It combines adaptive cognitive games, a voice-guided multilingual companion, health reminders, and a caregiver monitoring dashboard — all designed to work reliably even in low-connectivity, remote environments.

Our goal is to make cognitive care accessible, affordable, and culturally familiar for elderly users who have historically been left out of digital healthcare solutions.

---

## ✨ Key Features

### 1. Cognitive Games
- **Match It** — A memory-matching card game themed with NER-relevant imagery (local festivals, food, attire, animals) instead of generic visuals
- **Daily Routine Sequencing** — Patients arrange everyday activities in correct order, doubling as both engagement and an early cognitive assessment tool
- **Number/Word Recall** — Patients remember and sequence numbers/words; difficulty auto-scales based on performance
- Difficulty automatically scales based on patient performance (85% → bump; 50% → drop), using `game_level_config` as the single source of truth across backend and mobile

### 2. Caregiver Dashboard
- Flutter Web: real-time view of patient activity, game scores, and performance trends
- Reminder compliance tracking (medicine, water, food, exercise)
- Risk alerts for signs of cognitive decline or missed routines
- Multi-patient support for ASHA/health workers managing several patients

### 3. Reminders
- Scheduled voice-guided reminders for medicine, hydration, meals, and exercise
- Works fully offline via local device notifications
- Logs acknowledgment/compliance, synced to caregiver dashboard when online

### 4. Voice Companion
- Friendly conversational assistant guiding patients through the app
- Daily emotional wellbeing check-ins ("How are you feeling today?")
- Reduces reliance on reading/typing for navigation
- 10-language picker (provider-gated): assamese, bengali, hindi, english, mizo, manipuri, khasi, bodo, nepali; garo always renders as "not yet available"
- ASR (server-side) → LLM (reasoning) → TTS (patient's language); speech chain degrades gracefully when providers are unconfigured

### 5. Text-to-Speech & Speech-to-Text
- Converts app content into spoken audio and accepts voice input
- Powered by a multi-provider chain: Sarvam AI primary, AI4Bharat/Bhashini fallback
- Unsupported languages surface as "not yet available" — the UI never offers a language that fails when selected

### 6. Multilingual Support (NER Languages)
- Companion picker with 10 NER languages (assamese, bengali, hindi, english, mizo, manipuri, khasi, bodo, nepali, garo)
- Provider chain gating: some entries render "not yet available" when the active provider does not cover them
- All API responses accept `?language=assamese` parameter
- Mobile stores preferred_language per user; companion chat uses provider-gated 10-language picker
- Cultural content tied to selected language

### 7. Offline Support
- Fully functional patient-facing app with zero internet connectivity
- Local-first data storage with automatic background sync when reconnected
- Core game assets bundled on install to avoid repeated data usage

---

## 🏗️ System Architecture

```
┌─────────────────────────┐
│   Patient Mobile App      │  Flutter | Offline-first
│  (Games, Voice, Reminders)│
└───────────┬──────────────┘
            │ Local storage (drift SQLite)
            ▼
┌─────────────────────────┐
│   FastAPI Backend         │  Python | PostgreSQL
│  (REST API, risk-screening, difficulty, compliance)│
└───────────┬──────────────┘
            │ REST API
            ▼
┌─────────────────────────┐
│   Caregiver Dashboard      │  Flutter Web
│ (Trends, alerts, logs)     │
└─────────────────────────┘
```

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Patient App** | Flutter (Dart) |
| **Local Storage** | drift SQLite (offline store) |
| **Backend** | FastAPI + SQLAlchemy + Alembic + PostgreSQL |
| **AI/ML** | Python | OpenRouter (free-tier) | scikit-learn (risk-screening baseline) |
| **Speech** | Sarvam AI primary, AI4Bharat/Bhashini fallback |
| **Auth** | JWT (access + refresh with single-use rotation) |
| **Notifications** | console (logs + records deliveries) |
| **Offline Sync** | drift SQLite outbox + HTTP replay |
| **RAG Embeddings** | heuristic (deterministic md5-TF) |

---

## 📱 Target Users

- **Elderly dementia patients** in rural and remote NER areas
- **Family caregivers** seeking remote visibility into a loved one's cognitive health
- **ASHA and health workers** managing multiple elderly patients across villages
- **Healthcare institutions** in NER looking to extend cognitive care to underserved populations

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK >= 3.x
- Python >= 3.12
- PostgreSQL 16 (Homebrew `localhost:5432/eldercare`, system identifier `7681754862742343790`)
- Android Studio / Xcode for mobile builds (optional; CI builds in container)

### Running locally (September 30 demo)

**Do not use `docker compose up` for the demo.** The demo backend runs against
the populated Homebrew PostgreSQL at `localhost:5432/eldercare` (system
identifier `7681754862742343790`, existing 13 patients / 54 sessions / 10 documents /
13 consents) — not the separate, empty compose cluster at `192.168.23.25`. Do not
reseed or reset the demo database.

Full runbook — including the `.venv-demo` Python 3.12 environment, the cluster
preflight check, and the `ENABLE_BACKGROUND_JOBS=false` baseline — is in
**[DEPLOYMENT.md → "Run — September 30 demo"](DEPLOYMENT.md)**. Mobile:
`cd mobile && flutter pub get`, then on a device/emulator run
`adb -s SERIAL reverse tcp:8000 tcp:8000` and
`flutter run --debug -d SERIAL --dart-define=API_BASE_URL=http://localhost:8000`
(Android emulators reach the host via `http://10.0.2.2:8000` instead).

---

## 📊 Project Status

- [x] Problem research and requirement analysis
- [x] Tech stack finalization
- [x] Cognitive games (Match It, Daily Routine Sequencing, Number/Word Recall) — built + tested
- [x] Voice companion + multilingual pipeline — built + tested (emulator/macOS only; physical-device validation pending)
- [x] Multilingual support (10 NER languages in companion picker, provider-gated) — built + tested
- [x] Offline sync implementation (drift SQLite outbox + HTTP replay) — built + tested
- [x] Caregiver dashboard (Flutter Web, JWT-gated) — built + tested
- [x] AI adaptive difficulty engine (85/50 bands, 3-session rule, game_level_config as source of truth) — built + tested
- [ ] Physical-device voice validation — emulator/macOS only, outstanding
- [ ] Live API keys for Sarvam / AI4Bharat / Bhashini / OpenRouter — everything degrades gracefully when absent
- [ ] Risk-screening model: experimental / not clinically validated (separate ML system from gameplay decisions)
- [ ] Difficulty model remains shadow-mode only; rules sole authority for real decisions

---

## 🌍 Impact

- Improves cognitive well-being and quality of life for elderly dementia patients in remote NER areas
- Reduces caregiver burden through remote monitoring
- Supports early intervention research; the risk-screening model is experimental and not a claim about Smriti's outcomes
- Strengthens digital healthcare accessibility in an underserved region
- Low-cost, hardware-independent solution deployable on existing family devices

---

## 🎯 Smart India Hackathon 2026

This project is being developed for **Smart India Hackathon (SIH)** under the problem statement issued by the **Ministry of Development of North Eastern Region (MDoNER)**.

---

## 🙏 Acknowledgements

- Ministry of Development of North Eastern Region (MDoNER) for the problem statement
- Sarvam AI, AI4Bharat, Bhashini (National Language Translation Mission, Govt. of India) for multilingual voice infrastructure
- Smart India Hackathon for the platform and opportunity