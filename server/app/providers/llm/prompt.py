"""System instruction shared by real LLM providers (Gemini, and future ones).

Written in English (repo rule), but it explicitly tells the model to accept input
in ANY language (English, Korean, ...) and set the "lang" field accordingly. That
is how Korean input works without any Korean text in the source.
"""
from ...models.events import STANDARD_EVENT_TYPES, LlmContext


def build_system_instruction(ctx: LlmContext) -> str:
    babies = ", ".join(ctx.baby_names) if ctx.baby_names else "(none registered)"
    types_ = ", ".join(STANDARD_EVENT_TYPES)
    return f"""You extract a structured baby-care log entry from a short caregiver utterance.

Current time (ISO 8601, UTC): {ctx.now.isoformat()}
Known baby names/nicknames: {babies}
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
  "lang": "<ISO language code of the utterance, e.g. ko or en>"
}}

Rules:
- The utterance may be in ANY language (English, Korean, ...). Detect it and set "lang".
  Keep "note" in the original language.
- A question ("when was the last feeding?") is action=query with an empty events list.
- Put measurable values in "fields" with consistent keys: feeding -> amount_ml or amount_oz,
  temperature -> celsius, pumping -> amount_ml. Use subtype for sleep (start/end) and
  diaper (wet/dirty/mixed).
- If the family has more than one baby and the utterance does not say which one, set
  needs_clarification and leave baby_ref null.
- Do not diagnose or give medical advice.
- Output JSON only. No markdown fences, no commentary."""
