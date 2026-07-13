# Dayby

[![CI](https://github.com/hojoongdev/dayby/actions/workflows/ci.yml/badge.svg)](https://github.com/hojoongdev/dayby/actions/workflows/ci.yml)

**Voice-first baby-care logging for parents.** Say one sentence — an LLM structures it
into a record, your partner sees it in real time, and you get charts plus
natural-language analysis. Designed to be used every day, one-handed, while holding a
newborn: an iOS Action button or Shortcut logs an entry without even opening the app.

> Personal / portfolio project. It showcases three things working together:
> **MongoDB** (flexible document modeling for open-ended event data),
> **Flutter** (iOS-first cross-platform app), and
> **LLM orchestration** (provider-abstracted voice → structured records → analysis),
> all behind a **FastAPI** backend.

## Architecture

```
[Flutter app (iOS-first)]
  - Recording UI (mic / waveform / TTS reply)
  - Timeline, stats, analysis screens
  - Swift bridge: App Intents (Shortcuts, Action button, widgets)
        |  HTTPS
        v
[FastAPI server (Python)]
  - Auth abstraction  (mock / Google; sessions + refresh)
  - STT abstraction   (cloud / on-device / multimodal)
  - LLM abstraction   (swappable provider)
  - Ingest pipeline   (text / voice / photo -> create/update/delete/query)
  - Stats aggregation + LLM analysis
  - Change stream -> WebSocket (live family sync)
        |
        v
[MongoDB]  (flexible event documents, GridFS photos, oplog)
```

Every API key (LLM / STT) lives **only on the server** — never in the app.

## Tech stack

| Layer | Choice | Notes |
|---|---|---|
| App | Flutter (iOS first) | Android later |
| iOS integration | Swift + App Intents / WidgetKit | Shortcuts, Action button, widgets |
| Server | Python + FastAPI | async |
| Database | MongoDB (async PyMongo) | flexible document schema is the point |
| STT | provider abstraction | mock / Gemini audio, swappable |
| LLM | provider abstraction | mock / Gemini, swappable |
| Auth | provider abstraction | mock / Google, swappable |

## Status

Built in vertical slices — each phase ends in a running, demoable state.

- P1 — Server + DB + text logging — done
- P2 — Flutter app + voice (conversational chat, on-device STT, spoken replies) — done
- P3 — Query + conversation context + multiple babies — done; editing and deleting
  past entries by voice is still open
- P4 — Stats + real-time family sync — done
- **P5 — iOS Shortcuts / Action button / widgets** *(next; needs Xcode and a device)*
- P6 — LLM analysis + polish

## Quickstart

```bash
cp .env.example .env      # optional — sane defaults are baked into docker-compose
docker compose up --build
curl localhost:8000/health   # -> {"status":"ok","mongo":true}
```

No API keys required: the LLM and STT providers default to **mock** implementations,
so the whole pipeline runs offline.

MongoDB comes up as a single-node **replica set**. That is not about redundancy — it is
what change streams need, and change streams are how the live family sync works.

To sign in with a real Google account rather than the mock, both halves need the same
OAuth client — the server verifies what the app was issued:

```bash
AUTH_PROVIDER=google GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com docker compose up
cd app && flutter run --dart-define=GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
```

## Design highlights

- **Provider abstraction, mock first.** STT and LLM sit behind interfaces with at least
  a mock plus one real implementation, so the full flow runs with zero API keys and
  providers are swappable at runtime.
- **Flexible event schema.** Common event types keep standard fields (for stats);
  anything else is stored as-is in an open `fields` object. Validation happens at the
  API edge, not by locking down the database.
- **Safe by default.** Destructive actions (update / delete) always confirm first.
  Medical questions return a summary plus "consult a pediatrician" — never a diagnosis.
- **Family-scoped.** Every request is scoped to a family; no cross-family data access.
- **Live by change stream.** One parent logs, the other's phone updates. The server
  tails MongoDB's oplog for that family and pushes down a WebSocket — no polling, no
  message broker, no second copy of the truth.
- **The database counts, the model talks.** Proactive tips and the lifetime keepsake
  are both aggregations first: the numbers come out of MongoDB (`$facet`, a
  timezone-aware day/hour bucketing), and the model is given those and nothing else to
  write from. A warm sentence, never an invented one.
- **Mock-first everywhere, including identity.** `AUTH_PROVIDER=mock` runs the whole
  sign-in flow — session, refresh, family membership — with no Google project, exactly
  like the LLM and STT providers. Real providers slot in behind the same interface.
- **No language to choose.** `POST /ingest/voice` transcribes with Gemini audio, which
  is told nothing about the language and returns whatever was actually said — Korean,
  English, or a switch mid-sentence. On-device recognition has to be handed a locale
  first, which is the only reason the app still carries a KO/EN toggle.

## Repository layout

```
dayby/
├── docker-compose.yml     # FastAPI + MongoDB (local dev)
├── .env.example
├── server/                # FastAPI
│   └── app/
│       ├── main.py
│       ├── config.py
│       ├── db.py
│       ├── providers/     # llm/ , stt/  (interface + mock + real)
│       └── prompts/       # structuring / analysis prompts
├── app/                   # Flutter (added in P2)
│   └── ios/               # Swift: App Intents, widgets, bridge
└── docs/
```

## License

MIT — see [LICENSE](LICENSE).
