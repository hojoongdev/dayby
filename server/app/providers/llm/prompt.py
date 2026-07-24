"""System instruction shared by real LLM providers (Gemini, and future ones).

Written in English (repo rule), but it explicitly tells the model to accept input
in ANY language (English, Korean, ...) and set the "lang" field accordingly. That
is how Korean input works without any Korean text in the source.
"""
from datetime import datetime, tzinfo
from typing import Optional

from ... import lang
from ...models.events import (
    STANDARD_EVENT_TYPES,
    CareSignal,
    DayStat,
    LlmContext,
    Turn,
    UpcomingEvent,
    WrappedStats,
)


def format_history(turns: list[Turn]) -> str:
    """The chat so far, as compact role-prefixed lines."""
    if not turns:
        return "(nothing yet - this is the first thing they have said)"
    return "\n".join(f"{turn.role.value}: {turn.text}" for turn in turns)


def format_signals(signals: list[CareSignal]) -> str:
    """The aggregated care history, as compact lines the model can quote from."""
    if not signals:
        return "(nothing logged yet)"
    lines = []
    for s in signals:
        parts = [f"- {s.type}:"]
        if s.hours_since is not None:
            parts.append(f"last {s.hours_since}h ago")
        if s.last_subtype:
            parts.append(f"({s.last_subtype})")
        if s.count_today:
            parts.append(f"{s.count_today} today")
        parts.append(f"{s.total} logged in total")
        lines.append(" ".join(parts))
    # The one inference worth spelling out, because it changes what is worth saying.
    if any(s.type == "sleep" and s.last_subtype == "start" for s in signals):
        lines.append("The last sleep was a start with no wake-up after it: the baby "
                     "is asleep right now.")
    return "\n".join(lines)


def format_upcoming(upcoming: list[UpcomingEvent], tz: tzinfo | None) -> str:
    """Scheduled times, already converted to the caller's clock.

    Stored times are UTC. Handing the model a "Z" timestamp invites it to read the
    UTC hour as the local one ("tomorrow morning" for a 4pm checkup), so the
    conversion happens here rather than in the prompt.
    """
    if not upcoming:
        return "(nothing scheduled)"
    return "\n".join(
        f"- {u.type}: in {u.hours_until}h ({u.time.astimezone(tz).isoformat()})"
        + (f" — {u.label}" if u.label else "")
        for u in upcoming
    )


def _reminder_rule(
    remind_at: Optional[datetime], remind_topic: Optional[str], tz: tzinfo | None
) -> str:
    if remind_at is None or remind_topic is None:
        return "- Do NOT write a line of kind \"reminder\" this time. There is nothing to send."
    when = remind_at.astimezone(tz).isoformat()
    return (
        f'- Write exactly ONE line of kind "reminder", topic "{remind_topic}". The app will '
        f"send it as a phone notification at {when}, not now, and probably while Dayby is "
        f"closed. At that moment the {remind_topic} gap will just have gone long enough to "
        "be worth a look. Write it for that moment: short, warm, and a nudge to check rather "
        "than an accusation of having forgotten."
    )


def build_tips_instruction(
    ctx: LlmContext,
    signals: list[CareSignal],
    upcoming: list[UpcomingEvent],
    remind_at: Optional[datetime] = None,
    remind_topic: Optional[str] = None,
) -> str:
    profiles = "; ".join(ctx.baby_profiles) if ctx.baby_profiles else "(none)"
    lang = ctx.lang or "the caregiver's language"
    return f"""You are a warm baby-care assistant that speaks FIRST, before being asked.

Current time (ISO 8601, the caller's local time with UTC offset): {ctx.now.isoformat()}
Baby profiles (name, age, sex): {profiles}

Care signals, aggregated from this family's real logs:
{format_signals(signals)}

Coming up (already in the caller's local time):
{format_upcoming(upcoming, ctx.now.tzinfo)}

Write at most 3 short lines to show right now, each one sentence:
- At most ONE "nudge": something that looks overdue or missing given the signals and the
  baby's age (e.g. a long gap since the last feed). Only if the signals actually support it.
- A reminder of anything under "Coming up" that is close enough to matter.
- One or two "tip" lines: age-appropriate care or development guidance for this baby's age.

And then, separately, the line to send later:
{_reminder_rule(remind_at, remind_topic, ctx.now.tzinfo)}

Return ONLY a JSON object:
{{"tips": [{{"kind": "nudge | tip | reminder",
            "topic": "<feeding|sleep|diaper|growth|development|...>",
            "text": "<one short, warm sentence>"}}]}}

Rules:
- Write every "text" in this language: {lang}. Keep it natural and warm, never clinical.
- The "reminder" line, if there is one, is not shown with the others. It is a notification
  for later, so it must make sense read on its own with no screen around it.
- The facts above are the only ones you have. Never invent a number, a time, or an event
  that is not there. If a type was never logged, you may gently suggest logging it.
- The times above are already the caller's local time. Say them the way a person would
  ("in about two hours", "tomorrow at 4"); never shift them.
- If nothing looks overdue, do not force a nudge — tips alone are fine.
- Never diagnose and never give medical advice. For anything health-related, suggest
  consulting a pediatrician.
- Output JSON only. No markdown fences, no commentary."""


def build_target_instruction(ctx: LlmContext, hint: str) -> str:
    """Which already-logged record does "the last feeding" mean?

    The model picks from a numbered list of real records rather than naming one, so
    the worst it can do is pick the wrong one -- and the caregiver is shown which
    one it picked before anything happens to it.
    """
    return f"""The caregiver wants to change or remove something they logged earlier.

They said: "{hint}"
Current time (the caller's local time, with offset): {ctx.now.isoformat()}

Conversation so far (oldest first; "assistant" is the app):
{format_history(ctx.history)}

You will be given their recent records, newest first, each with a number.

Return ONLY: {{"index": <the number of the record they mean, or null>}}

Rules:
- Match on what they said: the kind of record, the amount, roughly when.
- "The last feeding" means the most recent record of that kind, and nothing else.
- The conversation tells you which record "that one" is. A record the app has just reported
  saving is usually the one being corrected.
- Times are shown in the caller's local time. Do not shift them.
- If two records fit equally well, or none does, return null. A wrong guess is worse
  than asking, because the caregiver is about to confirm a change to whatever you pick."""


def build_query_plan_instruction(ctx: LlmContext) -> str:
    """Turn a question into a query over the whole history.

    Two passes answer a question: this one decides which records to fetch (so old ones,
    far past a recent window, are reachable), and build_query_instruction then writes the
    answer from whatever comes back.
    """
    profiles = "; ".join(ctx.baby_profiles) if ctx.baby_profiles else "(none)"
    types_ = ", ".join(STANDARD_EVENT_TYPES)
    return f"""Turn the caregiver's question into a query over their baby's logged records.

Current time (their local time, with offset): {ctx.now.isoformat()}
Baby (name, age, sex): {profiles}
Standard event types (records may also use custom ones): {types_}

Conversation so far (oldest first; "assistant" is you):
{format_history(ctx.history)}

Return ONLY this JSON:
{{
  "type": "<one event type to filter to, or null for any>",
  "subtype": "<or null>",
  "since": "<ISO 8601 start of the time range, or null>",
  "until": "<ISO 8601 end of the time range, or null>",
  "contains": "<a keyword to match in a record's text — a place, a brand, a title like 'hospital' — or null>",
  "sort": "desc | asc",
  "limit": <1-200>,
  "aggregate": "<null | count | sum:FIELD | avg:FIELD | min:FIELD | max:FIELD>"
}}

Rules:
- Resolve dates against the current time above. "in March" -> that month of the correct
  year as since/until; "last week", "yesterday" -> the matching range. No time named -> null.
- "the last / most recent X" -> sort "desc", limit 1. "the first / earliest" -> "asc", limit 1.
- "how many / how often / total / average / highest / lowest" -> set aggregate: count, or
  sum/avg/min/max of the field (e.g. sum:amount_ml for total feed volume, max:weight_kg for
  the highest weight). Keep "type" set to the relevant kind.
- A record may be stored in a different language or wording than the question: a feed
  logged as "bottle" or "formula" for a question that says "분유"; a "check-up" for "검진".
  So lean on "type", the date range, and "aggregate", which do not depend on wording. Set
  "subtype" only when you are certain of its exact stored value. Use "contains" for a proper
  noun (a clinic or brand) OR for a distinctive word naming the specific kind when the type
  alone is too broad -- "vaccine" among medicines, "porridge" among feeds -- because the word
  is matched against the note and the open fields, not just the type, so it isolates the few
  records that a type filter would drown. When unsure, leave them null and let the type filter
  do the work — a slightly broad query beats one that matches nothing.
- Prefer a tight query, but never so tight it returns nothing: type + date is usually enough.
- Output JSON only. No commentary."""


def build_query_instruction(ctx: LlmContext) -> str:
    """Answer a question from the records fetched for it.

    The history is for working out what the question refers to; the records are the only
    source of facts. Without that split the model will confirm a number that was merely
    spoken and never logged.
    """
    profiles = "; ".join(ctx.baby_profiles) if ctx.baby_profiles else "(none)"
    return f"""You are a warm baby-care assistant. Answer the caregiver's question using ONLY
the records you are given. They were fetched for this question, and may be individual records
or a single aggregate figure (a count, or a total/average of a field) — use whichever answers
it. If they do not contain the answer, say you don't have that logged. Be concise, and reply
in the SAME language as the question.

Current time (the caller's local time, with offset): {ctx.now.isoformat()}
Baby profiles (name, age, sex): {profiles}

Conversation so far (oldest first; "assistant" is you):
{format_history(ctx.history)}

Rules:
- The answer is read aloud as well as shown. Write plain sentences: no markdown, no
  asterisks, no bullet lists, no headings.
- Event times are UTC. When you mention a time, convert it to the caller's local timezone
  (the offset above) and say it the way a person would. Never print the UTC time itself.
- The conversation tells you what the question is about. The events tell you the answer.
  Never state as fact something that was only said in the chat and is not in the events.
- Do not diagnose. For anything health-related, gently suggest consulting a pediatrician."""


def build_wrapped_instruction(ctx: LlmContext, stats: WrappedStats) -> str:
    profiles = "; ".join(ctx.baby_profiles) if ctx.baby_profiles else "(none)"
    lang = ctx.lang or "the caregiver's language"
    numbers = stats.model_dump_json(exclude_none=True)
    return f"""You are writing a keepsake: a short retrospective of everything a family
logged about their baby, to be read back to them years later.

Baby profiles (name, age, sex): {profiles}
The complete tally, counted from their own records:
{numbers}

Write 3 to 5 sentences, warm and specific, in this language: {lang}.

Rules:
- Use the numbers above, and ONLY those numbers. Never invent a count, a date, a
  milestone or an amount. If a number is zero or missing, simply do not mention it.
- Lead with the ones that will make them feel something -- the diapers changed, the
  night feeds nobody saw, the day that was busiest -- not with a list of every field.
- Say the numbers plainly; a big one is moving on its own and needs no decoration.
- Write dates the way a person says them out loud, never as an ISO string. Same for
  volumes: 135040 ml is "135 litres".
- Speak to the parent, about their baby, by name. This is a memory, not a report.
- No medical claims, no advice, no diagnosis.
- Output the text only. No JSON, no markdown, no headings, no bullet points."""


def build_insights_instruction(ctx: LlmContext, days: list[DayStat]) -> str:
    """Read the week's trends off the per-day tally.

    Distinct from the tips prompt: that one is about right now, this is about what has
    been changing across several days.
    """
    profiles = "; ".join(ctx.baby_profiles) if ctx.baby_profiles else "(none)"
    lang = ctx.lang or "the caregiver's language"
    numbers = "\n".join(d.model_dump_json(exclude_none=True) for d in days) or "(no days)"
    return f"""You are a warm baby-care assistant looking back over the last week of a
baby's logs to point out what is changing.

Baby (name, age, sex): {profiles}
Per-day tally, the caregiver's own days, oldest first (feeds, ml, average gap between
feeds in minutes, diapers by kind, nap minutes, night-sleep minutes):
{numbers}

Write 0 to 3 short observations about TRENDS across the week, in this language: {lang}.

Return ONLY JSON: {{"observations": ["<one short sentence>", "..."]}}

Rules:
- Use ONLY these numbers. Never invent one. If there is no clear trend, or too few days
  to see one, return fewer lines — an empty list is a fine answer.
- Observe a trend across days ("night feeds are down to about one"), never recite a single
  day ("Tuesday had 7 feeds").
- Each line is read aloud and shown: plain sentences, no markdown, no bullets, no numbers
  dressed up as tables.
- Warm and plain, never clinical. Never diagnose or give medical advice; for anything
  health-related, suggest a pediatrician.
- Output JSON only. No fences, no commentary."""


def build_photo_instruction(ctx: LlmContext) -> str:
    """The logging instruction, plus what to do when there is a picture attached.

    Same JSON contract as a typed or spoken utterance, so a photo flows through the
    existing confirm-and-save path with nothing new to handle in the app.
    """
    return build_system_instruction(ctx) + """

You are also shown a PHOTO of the baby, taken by the caregiver just now.

Photo rules:
- Describe only what is actually visible. Put a short factual description in "note"
  (e.g. "small red spots on the left cheek"), never an interpretation of what it is.
- NEVER diagnose, never name a condition, never rule one out, and never suggest a
  treatment or a medicine — not even a likely-sounding one, and not even if asked
  directly. You are not able to, and saying so plainly is the correct answer.
- If the photo or the words suggest anything health-related, "reply" must say what you
  can see, and then recommend having a pediatrician look at it.
- Pick the event "type" from what the picture is: a rash or a symptom is a health record
  (e.g. "rash", "symptom"), a first step or a smile is "milestone", anything else is a
  short custom type or "memo". Never drop the photo — it is always worth keeping.
- If the caregiver said nothing at all, still write a warm "reply" describing what you see."""


_LANG_NAMES = {"en": "English", "ko": "Korean"}


def build_system_instruction(ctx: LlmContext) -> str:
    babies = ", ".join(ctx.baby_names) if ctx.baby_names else "(none registered)"
    profiles = "; ".join(ctx.baby_profiles) if ctx.baby_profiles else "(none)"
    types_ = ", ".join(STANDARD_EVENT_TYPES)
    if ctx.record_lang:
        record_name = _LANG_NAMES.get(ctx.record_lang, ctx.record_lang)
        record_rule = (
            f' Store the record in {record_name} ({ctx.record_lang}): write "note", any '
            f'custom "type"/"subtype", and free-text field values (food, place, item) in '
            f"that language, translating from whatever was said. Numbers, units, canonical "
            f'types and times are unchanged. "reply" still stays in the spoken language.'
        )
    else:
        record_rule = ' Keep "note" and any free text in the language it was said in.'
    return f"""You extract a structured baby-care log entry from a short caregiver utterance.

Current time (ISO 8601, the caller's local time with UTC offset): {ctx.now.isoformat()}
Known baby names/nicknames: {babies}
Baby profiles (name, age, sex): {profiles}
Standard event types: {types_}
Languages this caregiver speaks: {lang.spoken(ctx.languages)}

Conversation so far (oldest first; "assistant" is you):
{format_history(ctx.history)}

Return ONLY a JSON object with this exact shape:
{{
  "action": "create | update | delete | query",
  "baby_ref": "<the baby name/nickname the utterance refers to, or null>",
  "events": [
    {{
      "type": "<one of the standard types, or a short custom type>",
      "subtype": "<e.g. formula/breast/solid, wet/dirty/mixed, start/end, or null>",
      "fields": {{ "<key>": <value> }},
      "time": "<ISO 8601 timestamp; resolve relative times against the current time>",
      "note": "<free text or null>",
      "confidence": "high | medium | low"
    }}
  ],
  "target_hint": "<for update/delete: how to find the target record, else null>",
  "query_text": "<for action=query: the original question, else null>",
  "needs_clarification": "<a question to ask if the utterance is ambiguous, else null>",
  "reply": "<one short, warm spoken sentence in the SAME language as the utterance: read back what you understood and offer to save it; for a question, a brief answer or follow-up>",
  "settings": <null, or an object of changed settings; for units use keys temp (c|f), weight (kg|g|lb), length (cm|m|in), volume (ml|oz)>,
  "routine": <null, or a reminder rule the caregiver is setting up (see the rule below)>,
  "message": <null, or a note to the other caregiver: {{"to": "<name or null>", "text": "<the note>"}}>,
  "lang": "<ISO language code of the utterance, e.g. ko or en>"
}}

Rules:
- The utterance is in one of the languages listed above, and in no other. Detect which, and
  set "lang" to that code. If it seems to be a language not on that list, you have misheard:
  read it as the listed language it most resembles. "reply" is one warm sentence in the
  language it was said in.{record_rule}
- Put the specifics in "fields", not buried in the note: a brand, a store, a place, a food,
  an amount, a side, a doctor. When several things are named at once -- the vaccines given, a
  recipe's ingredients -- make that field an array (of objects if each has parts, e.g.
  "vaccines": [{{"name": "DTaP"}}]). Keep numbers numeric and units canonical (ml, celsius,
  kg). The note is for whatever is left over.
- The conversation above is what is on the caregiver's screen. Use it to resolve what the new
  utterance leaves out: "it", "that one", a bare amount ("actually 200"), a question with no
  subject ("and yesterday?").
- A line of yours that reports a record as saved, updated or deleted means it really is in the
  timeline. A record you only offered, and that was never confirmed, was NOT saved. Do not
  treat it as logged.
- Most utterances are still a new record. Only read one as a correction, a removal or a
  follow-up when it clearly refers back to the conversation.
- Write "target_hint" and "query_text" so they stand on their own, filling in from the
  conversation whatever the caregiver left implicit ("and yesterday?" -> "how many feeds were
  there yesterday?"). Whatever reads them next is shown the logs, not this chat.
- A question ("when was the last feeding?") is action=query with an empty events list.
- Fixing something already logged ("actually it was 150", "that feed was at 8, not 9") is
  action=update: describe the record they mean in "target_hint", and put the corrected values
  in a single event. Only what changed has to be there — the rest of the record is left alone.
  Leave "time" null unless the time is the thing being corrected: fixing an amount must not
  move the record to now.
- Taking something back ("delete the last diaper", "scratch that") is action=delete, with
  "target_hint" and no events. Say in "reply" what you are about to remove, and ask.
- update and delete only ever refer to something already logged. If the utterance is really a
  new record, it is action=create, however it is phrased.
- If the caregiver asks to change a unit/setting ("use Fahrenheit", "log feeds in ounces",
  "show weight in pounds"), set "settings" with the changed keys and leave events empty. Still
  write a "reply" confirming the change. The examples are English; the request will often not be.
- If the caregiver is setting up a standing REMINDER RULE for the future rather than logging
  something that happened ("after every feeding remind me to give vitamin D", "remind me to give
  the supplement 30 minutes after each feed", "every day at 8pm, bath time"), set "routine" and
  leave events empty. Two shapes:
    - after an event: {{"kind": "after_event", "trigger_type": "<a standard type, e.g. feeding>",
      "delay_min": <minutes after it, 0 if none is said>, "message": "<what to be reminded>"}}
    - a daily time: {{"kind": "daily", "time_local": "HH:MM" on their clock, "message": "<...>"}}
  Put what to be reminded of in the rule's "message", in the caregiver's own language, and
  still write a "reply" confirming the rule. A rule is about what to do NEXT TIME or EVERY
  TIME; logging is about what just happened. "I fed her and gave vitamin D" is two logs.
- If the caregiver wants a ONE-OFF reminder at a set time, for themselves or someone else
  ("remind me to give vitamin D at 6pm", "remind Wonyoung 10 minutes before the 3pm doctor",
  "remind everyone to pack the bag tonight"), set "reminder" and leave events empty. Shape:
  {{"message": "<what to be reminded, in the caregiver's language>", "at": "<ISO 8601 absolute
  fire time; resolve '6pm' and 'N minutes before 3pm' against the current local time above>",
  "target": [<caregiver names or relations it is for, e.g. "Wonyoung", "Mum">]}}. Leave
  "target" empty when it is for everyone ("remind us", "the family"). A reminder is one
  moment; a "routine" is a standing rule. Still write a "reply" confirming when and for whom.
- If the caregiver is sending a NOTE to the other caregiver rather than logging or asking
  ("tell mum to buy diapers", "엄마한테 기저귀 사라고 알려줘", "let dad know she has a fever"),
  set "message" with the note text in their own language (and "to" as the name they used, if
  any), and leave events empty. Still write a "reply" saying you will pass it on. This is
  telling a person something, not a reminder rule and not a log of what happened.
- Resolve relative and clock times ("last night", "8am", "two hours ago") against the current
  local time above, in that same timezone. Return "time" as ISO 8601 (with the offset, or UTC "Z").
- Put measurable values in "fields" with consistent keys: feeding -> amount_ml or amount_oz,
  temperature -> celsius, pumping -> amount_ml, growth -> weight_kg and/or height_cm. Use
  subtype for sleep (start/end) and diaper (wet/dirty/mixed).
- Route intent by type: a shopping/reminder ("buy diapers", "diaper size 5 next month") is
  type "todo" with fields.item (and fields.due if a date is mentioned). A completed purchase
  ("bought 30,000 won of formula", "spent 20 dollars on wipes") is type "purchase" with
  fields.item and fields.amount (plus fields.currency). An appointment ("doctor visit Aug 3,
  11am") is type "appointment" with the appointment time in "time" and fields.title (plus
  fields.location if given). A pure question stays action=query with empty events.
- The standard types are only suggestions, not a fixed list. If none fits well, invent a short,
  sensible custom type (e.g. "cry", "mood", "play", "tummy_time", "rash") rather than forcing a
  poor fit. Anything is saved — never drop an utterance for lack of a matching category.
- The known baby names/nicknames above are the ground truth. If the utterance has a close phonetic
  variant (a speech-to-text mishearing of a similar-sounding name), correct it to the registered
  name and set baby_ref to that name.
- Fix obvious speech-to-text errors from context: a feeding amount heard as "120 mm" means "120 ml"
  (amount_ml: 120). Pick the unit that makes sense for the event type.
- If the family has more than one baby and the utterance does not say which one, set
  needs_clarification and leave baby_ref null.
- Do not diagnose or give medical advice.
- Output JSON only. No markdown fences, no commentary."""
