"""The languages a caregiver says they speak.

Narrowing the set is not a nicety. The transcriber is told nothing about the language and
returns whatever it believes it heard, so a Korean sentence muttered one-handed over a
crying baby comes back as Chinese often enough to matter. Being told which languages are
even possible removes that whole class of mistake.

It is a personal setting rather than a family one: one parent's shorter list is a tighter
constraint, and therefore a better one, than the household's union.
"""

LANGUAGES = {
    "ko": "Korean",
    "en": "English",
    "ja": "Japanese",
    "zh": "Chinese",
    "es": "Spanish",
    "fr": "French",
    "de": "German",
}

DEFAULT = ["ko", "en"]


def known(codes: list[str]) -> list[str]:
    """The codes we recognise, in the order given, with anything else dropped."""
    return [code for code in codes if code in LANGUAGES]


def spoken(codes: list[str]) -> str:
    """The caregiver's languages, named, for a prompt to lean on.

    Never empty. An empty list in a prompt is an open invitation to every language there
    is, which is the one thing this module exists to prevent, so it falls back rather than
    leaving the door open.
    """
    return ", ".join(f"{LANGUAGES[code]} ({code})" for code in known(codes) or DEFAULT)
