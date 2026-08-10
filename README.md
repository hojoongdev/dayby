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
- P5 — iOS Shortcuts / Action button / widgets — **partly done**. The Action button and its
  Siri phrase open the app already listening; home-screen widgets and Watch are not built
- P6 — LLM analysis — **done** (answers grounded in your own logs, proactive tips, the
  keepsake); polish is ongoing

Since then: reminder rules a family sets for itself (including by voice), forward predictions
and weekly trends, notes between caregivers, email+password accounts, and dark mode.

Verified on a real iPhone: recording, upload, transcription. The one thing still to confirm
on a device is where the silence detector decides a sentence has ended — see `voice.dart`.

## Quickstart

You need [Docker](https://docs.docker.com/get-started/get-docker/) for the server, and
[Flutter](https://docs.flutter.dev/get-started/install) 3.44+ for the app. No API keys:
the LLM, STT and TTS providers all default to **mock**, so the whole pipeline runs offline.

**1. Start the server**

```bash
git clone https://github.com/hojoongdev/dayby.git
cd dayby
cp .env.example .env      # optional — docker-compose has the same defaults baked in
docker compose up --build
curl localhost:8000/health   # -> {"status":"ok","mongo":true}
```

MongoDB comes up as a single-node **replica set**. That is not about redundancy — it is
what change streams need, and change streams are how the live family sync works. It is not
published to the host, so it will not collide with a MongoDB you already run. If port 8000
is taken, set `PORT` in `.env`.

**2. Run the app**

```bash
cd app
flutter pub get
flutter run -d chrome        # or: flutter run   (iOS simulator, or a connected iPhone)
```

It talks to `http://localhost:8000` out of the box. Chrome is the fastest look — recording
and spoken replies both work there; Face ID, scheduled notifications and Google Sign-In are
the parts that need a real phone. Android builds but has none of its permissions declared
yet, so it is iOS or the browser for now.

The server address is editable at runtime (**Settings → Server**), which is how you point a
phone at the machine running the server — they have to be on the same Wi-Fi, and a phone
cannot reach `localhost`:

```bash
ipconfig getifaddr en0       # the Mac's LAN address, e.g. 10.0.1.23
```

Type `http://10.0.1.23:8000` into Settings → Server. A build can also bake in a default
with `flutter run --dart-define=DAYBY_API=http://10.0.1.23:8000`.

**3. Fill it with a week of records (optional)**

An empty app has empty charts. The seed script writes plausible history straight into
MongoDB, dated in the past:

```bash
docker compose exec server python -m scripts.seed --latest --tz +09:00
```

`--latest` means the family you just created in the app; `--invite 5180d2` picks one by the
invite code shown in Settings. `--tz` should be your own offset, or the records land at the
wrong hours.

## Configuration

Everything below is optional — copy `.env.example` to `.env` and edit. See that file for
the full list.

**A real model instead of the mock.** `LLM_PROVIDER=gemini` and `STT_PROVIDER=gemini` with a
`GEMINI_API_KEY` from [AI Studio](https://aistudio.google.com/apikey). `TTS_PROVIDER=gemini`
adds a natural, language-aware voice; without it the app speaks with the device voice.

**Or your own local model.** `LLM_PROVIDER=local` points the same prompts at any
OpenAI-compatible `/chat/completions` endpoint, so Ollama or LM Studio can run the whole
thing on your machine:

```bash
LLM_PROVIDER=local OPENAI_BASE_URL=http://host.docker.internal:11434/v1 OPENAI_MODEL=llama3.1
```

**Sign-in.** `AUTH_PROVIDER` decides whether there is a sign-in screen at all:

| Value | What it is |
|---|---|
| `none` (default) | No accounts. The app names its family with a header — a development bypass, refused unless `APP_ENV=development` |
| `password` | Real accounts, email + password, no third party. Sign up in the app; a second parent signs up and joins with the invite code |
| `mock` | The sign-in flow with no keys — the token is the email you claim to be. Development only |
| `google` | Real Google Sign-In |

`password` is the one to use for two phones sharing a family. Set a real `JWT_SECRET` with it;
the server refuses to start with the shipped placeholder once auth is on outside development.

Google needs the same OAuth client on both halves — the server verifies what the app was
issued:

```bash
AUTH_PROVIDER=google GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com docker compose up
cd app && flutter run --dart-define=GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
```

## Tests

```bash
docker compose run --rm -e DB_NAME=dayby_test server \
  sh -c "uv pip install --system -q pytest pytest-asyncio httpx && pytest -q"

cd app && flutter test
```

The database name has to end in `_test` or the fixture that wipes it refuses to run. The one
test that calls the real Gemini API skips itself when `GEMINI_API_KEY` is absent. Both suites
are what CI runs on every push.

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
- **Rules a family sets for itself.** "After a feed, remind me about vitamin D in 30 minutes"
  becomes a stored rule, either from the Reminders screen or by saying it. The assistant turns
  the active ones into scheduled notifications, so they arrive with the app closed — local
  notifications, no push server.
- **It also speaks first.** Next feed and next nappy are predicted from the median gap in this
  baby's own recent rhythm, and dropped when that rhythm has gone stale; the week's trends come
  from the same day tally the charts use. Arithmetic first, the model only writes it up.
- **Bring your own model, even a local one.** `LLM_PROVIDER=local` points the same prompts
  at any OpenAI-compatible endpoint (a local Ollama or LM Studio), so the whole thing can
  run on your own machine with no hosted key.

## Repository layout

```
dayby/
├── docker-compose.yml       # FastAPI + MongoDB (local dev)
├── .env.example             # every setting, with what it does
├── server/                  # FastAPI
│   ├── app/
│   │   ├── routers/         # auth, families, ingest, events, photos, assistant, insights,
│   │   │                    # stats, wrapped, live, routines, reminders, messages, tts
│   │   ├── providers/       # llm/ , stt/ , tts/ , auth/  (interface + mock + real)
│   │   │   └── llm/prompt.py  # every instruction the model is ever given
│   │   ├── models/
│   │   ├── care.py          # what "overdue" means, shared by the server and the mock
│   │   └── context.py       # the babies and the chat every LLM call is handed
│   ├── scripts/seed.py      # a week of demo records, for empty charts
│   └── tests/
└── app/                     # Flutter
    ├── lib/
    │   ├── screens/         # dashboard, log (chat), timeline, stats, wrapped, settings,
    │   │                    # preferences, reminders, messages, onboarding, signin, lock
    │   ├── voice.dart       # recording, and when a sentence has ended
    │   ├── config.dart      # the default server address
    │   └── api/
    ├── test/
    └── ios/
```

## License

MIT — see [LICENSE](LICENSE).
