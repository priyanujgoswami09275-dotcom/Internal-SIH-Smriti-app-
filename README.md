# Smriti — AI-Powered Cognitive Gaming and Memory Assistance Platform

**Empowering elderly dementia patients in the North Eastern Region through adaptive cognitive care.**

Smriti Reviving Memories, Restoring Smiles.

---

## 📋 Problem Statement

| | |
|---|---|
| **Problem Statement ID** | 26003 |
| **Title** | AI-Based Cognitive Gaming and Memory Assistance Platform for Elderly Dementia Patients in North Eastern Region (NER) |
| **Organization** | Ministry of Development of North Eastern Region (MDoNER) |
| **Category** | Software |
| **Theme** | MedTech / BioTech / HealthTech |

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
- Difficulty automatically scales based on patient performance

### 2. Caregiver Dashboard
- Real-time view of patient activity, game scores, and performance trends
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

### 5. Text-to-Speech & Speech-to-Text
- Converts app content into spoken audio and accepts voice input
- Pre-recorded native-speaker audio for core prompts to maximize clarity for elderly users
- Powered by Bhashini API and Google Cloud Speech APIs

### 6. Multilingual Support (NER Languages)
- Assamese, Bengali, Bodo, Khasi, Mizo, Manipuri (Meiteilon), Nepali, Hindi, English
- Region-specific cultural content tied to selected language

### 7. Offline Support
- Fully functional patient-facing app with zero internet connectivity
- Local-first data storage with automatic background sync when reconnected
- Core game assets bundled on install to avoid repeated data usage

---

## 🏗️ System Architecture

```
┌─────────────────────────┐
│   Patient App Layer      │  Flutter | Offline-first
│  (Games, Voice, Reminders)│
└───────────┬──────────────┘
            │ Local storage (SQLite/Hive)
            ▼
┌─────────────────────────┐
│   AI/Adaptive Layer       │  Python | scikit-learn
│ (Difficulty scaling,      │  FastAPI microservice
│  decline trend detection) │
└───────────┬──────────────┘
            │ Sync on reconnect
            ▼
┌─────────────────────────┐
│  Caregiver Dashboard      │  React.js | Firebase
│ (Trends, alerts, logs)    │
└─────────────────────────┘
```

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Patient App** | Flutter (Dart) |
| **Local Storage** | Hive / SQLite |
| **Caregiver Dashboard** | React.js, Tailwind CSS, Recharts |
| **Backend** | Firebase (Firestore, Auth, Cloud Functions) |
| **AI/ML** | Python, scikit-learn, FastAPI |
| **Voice & Language** | Bhashini API, Google Cloud Speech-to-Text/Text-to-Speech |
| **Notifications** | Firebase Cloud Messaging, flutter_local_notifications |
| **Offline Sync** | Firestore offline persistence / local SQLite sync queue |
| **Connectivity Detection** | connectivity_plus (Flutter) |

---

## 📱 Target Users

- **Elderly dementia patients** in rural and remote NER areas
- **Family caregivers** seeking remote visibility into a loved one's cognitive health
- **ASHA and health workers** managing multiple elderly patients across villages
- **Healthcare institutions** in NER looking to extend cognitive care to underserved populations

---

## 🚀 Getting Started

### Prerequisites
```
Flutter SDK >= 3.x
Node.js >= 18.x
Python >= 3.10
Firebase CLI
```

### Running locally (September 30 demo)

**Do not use `docker compose up` for the demo.** The demo backend runs against
the populated Homebrew PostgreSQL at `localhost:5432/eldercare` (system
identifier `7681754862742343790`, existing 13 patients / 10 documents) — not the
separate, empty compose cluster at `192.168.23.25`. Do not reseed or reset the
demo database.

Full runbook — including the `.venv-demo` Python 3.12 environment, the
cluster preflight check, and the `ENABLE_BACKGROUND_JOBS=false` baseline — is in
**[DEPLOYMENT.md → "Run — September 30 demo"](DEPLOYMENT.md)**. Mobile:
`cd mobile && flutter pub get`, then on a device/emulator run
`adb -s SERIAL reverse tcp:8000 tcp:8000` and
`flutter run --debug -d SERIAL --dart-define=API_BASE_URL=http://localhost:8000`
(Android emulators reach the host via `http://10.0.2.2:8000` instead).

## 📊 Project Status

- [x] Problem research and requirement analysis
- [x] Tech stack finalization
- [ ] Cognitive games (Match It, Daily Routine Sequencing) — in progress
- [ ] Voice companion + TTS/STT integration
- [ ] Multilingual support
- [ ] Offline sync implementation
- [ ] Caregiver dashboard
- [ ] AI adaptive difficulty engine
- [ ] Field testing

---

## 🌍 Impact

- Improves cognitive well-being and quality of life for elderly dementia patients in remote NER areas
- Reduces caregiver burden through remote monitoring
- Supports early intervention, which research shows can meaningfully slow dementia progression
- Strengthens digital healthcare accessibility in an underserved region
- Low-cost, hardware-independent solution deployable on existing family devices

---

## 🎯 Smart India Hackathon 2026

This project is being developed for **Smart India Hackathon (SIH)** under the problem statement issued by the **Ministry of Development of North Eastern Region (MDoNER)**.

---

## 🙏 Acknowledgements

- Ministry of Development of North Eastern Region (MDoNER) for the problem statement
- Bhashini (National Language Translation Mission, Govt. of India) for multilingual voice infrastructure
- Smart India Hackathon for the platform and opportunity
