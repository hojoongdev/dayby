# Dayby

[![CI](https://github.com/hojoongdev/dayby/actions/workflows/ci.yml/badge.svg)](https://github.com/hojoongdev/dayby/actions/workflows/ci.yml)

**Voice-first baby-care logging for parents.** Say one sentence — an LLM turns it into a
record, your partner's phone shows it a moment later, and you can ask about it afterwards
in plain language and be answered from your own logs. Built to be used one-handed, while
holding a newborn.

> Personal / portfolio project. It showcases three things working together:
> **MongoDB** (flexible document modeling for open-ended event data),
> **Flutter** (iOS-first cross-platform app), and
> **LLM orchestration** (provider-abstracted voice → structured records → analysis),
> all behind a **FastAPI** backend.

## Architecture

```
[Flutter app (iOS-first)]
  - Chat: record -> confirm card -> save; spoken replies
  - Home dashboard, timeline, keepsake
        |  HTTPS
        v
[FastAPI server (Python)]
  - Auth abstraction  (mock / Google; sessions + refresh)
  - STT abstraction   (mock / Gemini audio)
  - LLM abstraction   (mock / Gemini / local, OpenAI-compatible)
  - Ingest pipeline   (text / voice / photo -> create/update/delete/query)
  - Aggregations -> LLM (proactive tips, the keepsake)
  - Change stream -> WebSocket (live family sync)
        |
        v
[MongoDB]  (flexible event documents, GridFS photos, oplog)
```

Every API key (LLM / STT) lives **only on the server** — never in the app.

Not built yet: the remaining Swift surfaces (widgets, Watch). The Action button and its
App Intent are in, and need a release build on a device to exercise.

## Tech stack

| Layer | Choice | Notes |
|---|---|---|
| App | Flutter (iOS first) | Android later |
| Server | Python + FastAPI | async |
| Database | MongoDB (async PyMongo) | flexible document schema is the point |
| STT | provider abstraction | mock / Gemini audio, swappable |
| LLM | provider abstraction | mock / Gemini / local (OpenAI-compatible), swappable |
| Auth | provider abstraction | mock / Google, swappable |
| iOS integration | Swift + App Intents / WidgetKit | **planned, not built** |

## Status

Built in vertical slices — each phase ends in a running, demoable state.

- P1 — Server + DB + text logging — **done**
- P2 — Flutter app + voice: conversational chat, spoken replies, photos — **done**
- P3 — Conversation context, query, edit / delete by voice, multiple babies — **done**
- P4 — Stats and real-time family sync — **done**. The charts read a windowed aggregation
  (day / week / month / all); one parent's log updates the other's phone over a change stream.
- P5 — iOS Shortcuts / Action button / widgets — **not started**; needs Swift and a device
- P6 — LLM analysis — **done** (answers grounded in your own logs, proactive tips, the
  keepsake); polish is ongoing

Verified on a real iPhone: recording, upload, transcription. The one thing still to confirm
on a device is where the silence detector decides a sentence has ended — see `voice.dart`.

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
  first; moving the listening to the server is what let the app delete its KO/EN toggle.
- **The chat is the memory.** What the assistant is given of the conversation is exactly
  the bubbles on the screen, the ones reporting a save included — so "actually 200"
  corrects the feed that really got written, never one that was merely offered and then
  cancelled. It is shown no ids, so it cannot name a record that does not exist: it picks
  from real records by position, and the caregiver confirms which one before anything
  happens to it.
- **The room sets the threshold.** With the server doing the listening, the app has to
  decide for itself when a sentence has ended. A real iPhone in a real room reads a noise
  floor of -29 dBFS where a quiet bedroom reads -50, so no hardcoded level survives both.
  It measures the room at the top of every recording instead. It can fail only one way:
  the recording runs on and you tap stop, never that it cuts you off mid-sentence.
- **Records in the language you choose.** Speak Korean, file the record in English — the
  stored note, custom labels and food come back translated while the spoken reply stays in
  the language you said it in, and the numbers, units and times never move.
- **A window, not the recent hundred.** Records and Analysis fetch the range you pick — a
  day, a week, a month, all of it — from the server's `from`/`to`, so a long history is not
  hidden behind whatever last loaded on screen.
- **Bring your own model, even a local one.** `LLM_PROVIDER=local` points the same prompts
  at any OpenAI-compatible endpoint (a local Ollama or LM Studio), so the whole thing can
  run on your own machine with no hosted key.

## Repository layout

```
dayby/
├── docker-compose.yml       # FastAPI + MongoDB (local dev)
├── .env.example
├── server/                  # FastAPI
│   ├── app/
│   │   ├── routers/         # ingest, events, families, photos, assistant, wrapped, live, auth
│   │   ├── providers/       # llm/ , stt/ , auth/  (interface + mock + real)
│   │   │   └── llm/prompt.py  # every instruction the model is ever given
│   │   ├── models/
│   │   ├── care.py          # what "overdue" means, shared by the server and the mock
│   │   └── context.py       # the babies and the chat every LLM call is handed
│   └── tests/
└── app/                     # Flutter
    ├── lib/
    │   ├── screens/         # home, log (chat), timeline, settings, wrapped
    │   ├── voice.dart       # recording, and when a sentence has ended
    │   └── api/
    ├── test/
    └── ios/
```

## License

MIT — see [LICENSE](LICENSE).
