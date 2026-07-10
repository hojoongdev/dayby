# Dayby

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
  - Auth (family accounts)
  - STT abstraction   (cloud / on-device / multimodal)
  - LLM abstraction   (swappable provider)
  - Ingest pipeline   (structure text/voice into create/update/delete/query)
  - Stats aggregation + LLM analysis
        |
        v
[MongoDB]  (flexible event documents)
```

Every API key (LLM / STT) lives **only on the server** — never in the app.

## Tech stack

| Layer | Choice | Notes |
|---|---|---|
| App | Flutter (iOS first) | Android later |
| iOS integration | Swift + App Intents / WidgetKit | Shortcuts, Action button, widgets |
| Server | Python + FastAPI | async |
| Database | MongoDB (async PyMongo) | flexible document schema is the point |
| STT | provider abstraction | mock / cloud / multimodal, swappable |
| LLM | provider abstraction | mock / hosted, swappable |

## Status

Built in vertical slices — each phase ends in a running, demoable state.

- P1 — Server + DB + text logging — done
- **P2 — Flutter app + voice** *(current)*
- P3 — Edit / delete / query + conversation context + multiple babies
- P4 — Stats + real-time family sync
- P5 — iOS Shortcuts / Action button / widgets
- P6 — LLM analysis + polish

## Quickstart

```bash
cp .env.example .env      # optional — sane defaults are baked into docker-compose
docker compose up --build
curl localhost:8000/health   # -> {"status":"ok","mongo":true}
```

No API keys required: the LLM and STT providers default to **mock** implementations,
so the whole pipeline runs offline.

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
