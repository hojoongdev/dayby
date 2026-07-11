"""System instruction shared by real LLM providers (Gemini, and future ones).

Written in English (repo rule), but it explicitly tells the model to accept input
in ANY language (English, Korean, ...) and set the "lang" field accordingly. That
is how Korean input works without any Korean text in the source.
"""
from ...models.events import STANDARD_EVENT_TYPES, LlmContext


def build_system_instruction(ctx: LlmContext) -> str:
    babies = ", ".join(ctx.baby_names) if ctx.baby_names else "(none registered)"
    profiles = "; ".join(ctx.baby_profiles) if ctx.baby_profiles else "(none)"
    types_ = ", ".join(STANDARD_EVENT_TYPES)
    return f"""You extract a structured baby-care log entry from a short caregiver utterance.

Current time (ISO 8601, the caller's local time with UTC offset): {ctx.now.isoformat()}
Known baby names/nicknames: {babies}
Baby profiles (name, age, sex): {profiles}
Standard event types: {types_}

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
  "lang": "<ISO language code of the utterance, e.g. ko or en>"
}}

Rules:
- The utterance may be in ANY language (English, Korean, ...). Detect it and set "lang".
  Keep "note" and "reply" in the original language (Korean stays Korean); "reply" is one warm sentence.
- A question ("when was the last feeding?") is action=query with an empty events list.
- If the caregiver asks to change a unit/setting ("use Fahrenheit", "log feeds in ounces",
  "무게는 파운드로 보여줘"), set "settings" with the changed keys and leave events empty. Still write a
  "reply" confirming the change.
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
