"""Fill a baby's timeline with a week of plausible care records.

A development tool. It writes to MongoDB directly because the point is to date records
in the past, and POST /events stamps them as they arrive.

    docker compose exec server python -m scripts.seed --tz +09:00
    docker compose exec server python -m scripts.seed --invite 155649 --replace
"""
import argparse
import asyncio
import random
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Optional

from app.db import close_client, get_db
from app.util import invite_code, new_id, now as utc_now

DAYS_A_MONTH = 30.44

# Weighted by repetition, which is shorter than carrying a table of weights around.
DIAPER_KINDS = ("wet", "wet", "wet", "wet", "dirty", "dirty", "mixed")
SOURCES = ("voice",) * 6 + ("text",) * 3 + ("intent",)
BRANDS = ("Similac", "Hipp", "Aptamil", "Enfamil")
SOLIDS = ("rice porridge", "carrot puree", "banana", "sweet potato", "pumpkin puree")
NAP_PLACES = ("crib", "crib", "crib", "stroller", "car seat", "carrier")

MILESTONES = (
    "rolled over on their own",
    "first proper laugh",
    "grabbed a rattle and held on",
    "slept through until 5am",
    "found their feet",
    "babbled back at me",
)
MEMOS = (
    "fussy all afternoon, might be teething",
    "loved the bath tonight",
    "grandma visited",
    "took the bottle from dad without a fight",
)
PURCHASES = (("nappies, size 3", 34), ("formula, 2 tins", 48), ("sleep sacks", 26))
# Rough, and only so a demo does not read "32 KRW for nappies".
RATES = {"USD": 1, "EUR": 0.9, "GBP": 0.8, "KRW": 1350, "JPY": 150}


@dataclass(frozen=True)
class Rhythm:
    """Roughly what a day looks like at a given age."""

    feeds: tuple[int, int]
    feed_ml: tuple[int, int]
    naps: tuple[int, int]
    nap_min: tuple[int, int]
    night_feeds: tuple[int, int]
    diapers: tuple[int, int]
    solids: bool


RHYTHMS = (
    (1, Rhythm((8, 10), (60, 90), (4, 5), (35, 80), (2, 3), (8, 11), False)),
    (3, Rhythm((7, 8), (100, 140), (3, 4), (40, 90), (1, 2), (7, 9), False)),
    (6, Rhythm((6, 7), (140, 190), (3, 3), (45, 100), (0, 1), (6, 8), False)),
    (9, Rhythm((5, 6), (180, 220), (2, 3), (50, 110), (0, 1), (5, 7), True)),
    (999, Rhythm((4, 5), (200, 240), (2, 2), (60, 120), (0, 0), (5, 6), True)),
)


def rhythm_at(age_months: float) -> Rhythm:
    return next(r for limit, r in RHYTHMS if age_months < limit)


def _at(day: date, minutes: int, tz: timezone) -> datetime:
    """Local time, given as minutes past that day's midnight. May run past 1440."""
    return datetime.combine(day, time(0), tz) + timedelta(minutes=minutes)


class Timeline:
    """Collects event documents, and remembers whether the baby is asleep.

    Only the waking-up carries `duration_min`, which is the field /stats reads, so the
    start that it ends has to be tracked as the days are built.
    """

    def __init__(
        self,
        rng: random.Random,
        family_id: str,
        baby_id: str,
        members: list[str],
        cutoff: datetime,
    ) -> None:
        self.rng = rng
        self.family_id = family_id
        self.baby_id = baby_id
        self.members = members
        self.cutoff = cutoff
        self.events: list[dict] = []
        self.asleep_since: Optional[datetime] = None

    def add(
        self,
        at: datetime,
        type_: str,
        *,
        subtype: Optional[str] = None,
        fields: Optional[dict[str, Any]] = None,
        note: Optional[str] = None,
        raw_text: Optional[str] = None,
        future: bool = False,
    ) -> Optional[dict]:
        # Nothing routine is logged ahead of now: the seeded week has to look like it
        # was lived, which means today is a part of a day. Appointments opt out.
        if at > self.cutoff and not future:
            return None

        doc = {
            "_id": new_id(),
            "family_id": self.family_id,
            "baby_id": self.baby_id,
            "type": type_,
            "subtype": subtype,
            "fields": fields or {},
            "time": at.astimezone(timezone.utc),
            "note": note,
            "source": self.rng.choice(SOURCES),
            "raw_text": raw_text,
            "created_by": self.rng.choice(self.members) if self.members else None,
            "created_at": min(at, self.cutoff).astimezone(timezone.utc),
        }
        self.events.append(doc)
        return doc

    def sleep_start(self, at: datetime, where: str) -> None:
        if self.add(at, "sleep", subtype="start", fields={"where": where},
                    raw_text="down for a nap"):
            self.asleep_since = at

    def sleep_end(self, at: datetime) -> None:
        """A wake-up only means something if there is a sleep for it to close."""
        if self.asleep_since is None:
            return
        minutes = round((at - self.asleep_since).total_seconds() / 60)
        if minutes <= 0:
            return
        if self.add(at, "sleep", subtype="end", fields={"duration_min": minutes},
                    raw_text="awake now"):
            self.asleep_since = None


def _feed(t: Timeline, at: datetime, r: Rhythm, rng: random.Random) -> None:
    kind = rng.choices(
        ("bottle", "breast", "solid"), weights=(65, 30, 14 if r.solids else 0)
    )[0]

    if kind == "bottle":
        ml = rng.randrange(r.feed_ml[0], r.feed_ml[1] + 1, 10)
        fields: dict[str, Any] = {"amount_ml": ml}
        if rng.random() < 0.5:
            fields["brand"] = rng.choice(BRANDS)
        t.add(at, "feeding", subtype="bottle", fields=fields, raw_text=f"{ml} ml of formula")
    elif kind == "breast":
        side = rng.choice(("left", "right"))
        minutes = rng.randint(10, 22)
        t.add(at, "feeding", subtype="breast",
              fields={"side": side, "duration_min": minutes},
              raw_text=f"nursed {minutes} minutes on the {side}")
    else:
        food = rng.choice(SOLIDS)
        grams = rng.choice((30, 40, 50, 60))
        t.add(at, "feeding", subtype="solid", fields={"food": food, "amount_g": grams},
              raw_text=f"ate some {food}")


def _diaper(t: Timeline, at: datetime, rng: random.Random) -> None:
    kind = rng.choice(DIAPER_KINDS)
    t.add(at, "diaper", subtype=kind, raw_text=f"{kind} nappy")


def _day(t: Timeline, day: date, tz: timezone, rng: random.Random, age_months: float) -> None:
    r = rhythm_at(age_months)
    wake = _at(day, rng.randint(375, 450), tz)
    bedtime = _at(day, rng.randint(1170, 1275), tz)

    # Every night waking is a sleep that ended, a feed, and a sleep that started again.
    night = sorted(rng.sample(range(60, 300, 15), rng.randint(*r.night_feeds)))
    for minutes in night:
        woke = _at(day, minutes, tz)
        t.sleep_end(woke)
        _feed(t, woke + timedelta(minutes=4), r, rng)
        if rng.random() < 0.6:
            _diaper(t, woke + timedelta(minutes=10), rng)
        t.sleep_start(woke + timedelta(minutes=rng.randint(20, 35)), "crib")

    t.sleep_end(wake)

    count = max(3, rng.randint(*r.feeds) - len(night))
    step = (bedtime - wake).total_seconds() / 60 / count
    feeds = [wake + timedelta(minutes=step * i + rng.randint(-18, 18)) for i in range(count)]

    # Eat, play, sleep: a nap follows a feed rather than landing anywhere.
    nap_count = min(rng.randint(*r.naps), len(feeds) - 1)
    for i in sorted(rng.sample(range(len(feeds) - 1), nap_count)):
        start = feeds[i] + timedelta(minutes=rng.randint(25, 45))
        room = (feeds[i + 1] - start).total_seconds() / 60 - 10
        length = min(rng.randint(*r.nap_min), int(room))
        if length < 20:
            continue
        t.sleep_start(start, rng.choice(NAP_PLACES))
        t.sleep_end(start + timedelta(minutes=length))

    for at in feeds:
        _feed(t, at, r, rng)

    changes = max(0, rng.randint(*r.diapers) - len(night))
    for i in range(changes):
        if i < len(feeds) and rng.random() < 0.7:
            at = feeds[i] + timedelta(minutes=rng.randint(-12, 25))
        else:
            at = wake + timedelta(minutes=rng.randint(0, int((bedtime - wake).total_seconds() / 60)))
        _diaper(t, at, rng)

    if rng.random() < 0.7:
        t.add(bedtime - timedelta(minutes=rng.randint(30, 75)), "bath",
              fields={"duration_min": rng.randint(8, 15)}, raw_text="bath time")

    t.sleep_start(bedtime, "crib")


def _extras(
    t: Timeline,
    days: list[date],
    tz: timezone,
    rng: random.Random,
    birth: date,
    currency: str,
) -> None:
    """The things that do not happen every day. This is most of the type variety."""
    rate = RATES.get(currency, 1)
    # Today is only part of a day, and anything dated after now is dropped. The
    # once-a-week things go on a day that has already finished, so they always land.
    settled = days[:-1] or days

    for day in (days[0], settled[-1]):
        months = (day - birth).days / DAYS_A_MONTH
        t.add(_at(day, 600, tz), "growth", fields={
            "weight_kg": round(3.3 + months * 0.62 + rng.uniform(-0.1, 0.1), 2),
            "height_cm": round(50 + months * 2.2 + rng.uniform(-0.5, 0.5), 1),
            "head_cm": round(35 + months * 1.1 + rng.uniform(-0.3, 0.3), 1),
        }, raw_text="weighed and measured today")

    for day in days:
        if rng.random() < 0.8:
            t.add(_at(day, rng.randint(540, 600), tz), "medicine",
                  fields={"name": "vitamin D", "dose_ml": 1}, raw_text="vitamin D drops")
        if rng.random() < 0.55:
            t.add(_at(day, rng.randint(600, 1020), tz), "tummy_time",
                  fields={"duration_min": rng.choice((5, 8, 10, 12))},
                  raw_text="tummy time")
        if rng.random() < 0.4:
            t.add(_at(day, rng.randint(870, 1050), tz), "walk",
                  fields={"duration_min": rng.choice((20, 30, 45))},
                  raw_text="walk around the block")
        if rng.random() < 0.45:
            t.add(_at(day, rng.randint(480, 1200), tz), "pumping",
                  fields={"amount_ml": rng.randrange(60, 141, 10),
                          "side": rng.choice(("left", "right", "both"))},
                  raw_text="pumped after the morning feed")

    # One rough day, so the charts have something other than a flat week on them.
    sick = days[len(days) // 2]
    t.add(_at(sick, 1140, tz), "temperature", fields={"temp_c": 38.1},
          note="warm to the touch", raw_text="temperature is 38.1")
    t.add(_at(sick, 1170, tz), "medicine",
          fields={"name": "infant paracetamol", "dose_ml": 2.5},
          raw_text="gave paracetamol")
    t.add(_at(sick, 1200, tz), "memo", note="unsettled evening, keeping an eye on it")
    t.add(_at(days[min(len(days) - 1, len(days) // 2 + 1)], 555, tz), "temperature",
          fields={"temp_c": 36.8}, raw_text="temperature back to normal")

    for day in rng.sample(settled, min(2, len(settled))):
        t.add(_at(day, rng.randint(600, 1140), tz), "milestone",
              note=rng.choice(MILESTONES), raw_text="something to remember")
    for day in rng.sample(settled, min(2, len(settled))):
        t.add(_at(day, rng.randint(900, 1200), tz), "memo", note=rng.choice(MEMOS))

    for day, (item, usd) in zip(rng.sample(settled, min(len(PURCHASES), len(settled))), PURCHASES):
        t.add(_at(day, rng.randint(660, 1200), tz), "purchase",
              fields={"item": item, "amount": round(usd * rate), "currency": currency},
              raw_text=f"bought {item}")

    today = days[-1]
    t.add(_at(days[max(0, len(days) - 5)], 630, tz), "appointment",
          fields={"title": "4-month check-up", "location": "Dr. Park"},
          raw_text="check-up this morning")
    t.add(_at(today, 2 * 1440 + 615, tz), "appointment",
          fields={"title": "vaccination", "location": "Dr. Park"},
          raw_text="vaccination in two days", future=True)
    t.add(_at(today, 5 * 1440 + 900, tz), "appointment",
          fields={"title": "paediatrician follow-up"},
          raw_text="follow-up next week", future=True)

    t.add(_at(days[-2] if len(days) > 1 else today, 720, tz), "todo",
          fields={"title": "order size 4 nappies", "done": False},
          raw_text="remind me to order nappies")
    t.add(_at(days[0], 720, tz), "todo",
          fields={"title": "book the check-up", "done": True})
    t.add(_at(today, 3 * 1440 + 600, tz), "todo",
          fields={"title": "restock formula", "done": False}, future=True)


def build_events(
    *,
    family_id: str,
    baby_id: str,
    birthdate: date,
    members: list[str],
    days: int,
    tz: timezone,
    now: datetime,
    seed: int,
    currency: str = "USD",
) -> list[dict]:
    """A week of records for one baby, oldest first. Pure: no database, no clock."""
    rng = random.Random(seed)
    local_now = now.astimezone(tz)
    t = Timeline(rng, family_id, baby_id, members, local_now)

    dates = [local_now.date() - timedelta(days=n) for n in range(days - 1, -1, -1)]
    # The window has to start somewhere, and it may as well start with the baby asleep,
    # so the first morning is a wake-up with a real night behind it.
    t.asleep_since = _at(dates[0] - timedelta(days=1), 1215, tz)

    for day in dates:
        _day(t, day, tz, rng, (day - birthdate).days / DAYS_A_MONTH)
    _extras(t, dates, tz, rng, birthdate, currency)

    t.events.sort(key=lambda doc: doc["time"])
    return t.events


def parse_tz(value: str) -> timezone:
    """"+09:00", "+0900" and "9" all mean the same thing."""
    text = value.strip()
    sign = -1 if text.startswith("-") else 1
    text = text.lstrip("+-")
    if ":" in text:
        hours, _, minutes = text.partition(":")
    elif len(text) == 4:
        hours, minutes = text[:2], text[2:]
    else:
        hours, minutes = text, "0"
    return timezone(sign * timedelta(hours=int(hours), minutes=int(minutes)))


async def _resolve_baby(db, args) -> tuple[dict, dict]:
    if args.invite:
        family = await db.families.find_one({"invite_code": args.invite.strip()})
    elif args.family:
        family = await db.families.find_one({"_id": args.family})
    elif args.latest:
        # The one you just made in the app. Saves reading its id back out of Settings:
        # onboard, then `--latest --replace` fills that same family.
        family = await db.families.find_one(sort=[("created_at", -1)])
        if family:
            print(f"Latest family: {family['name']} ({family['_id']})")
    else:
        family = None

    if family is None and (args.invite or args.family or args.latest):
        raise SystemExit("No such family. Onboard in the app first, or pass --invite.")

    if family is None:
        family = {
            "_id": new_id(),
            "name": args.family_name,
            "members": [],
            "created_at": utc_now(),
            "invite_code": invite_code(),
            "invite_expires_at": utc_now() + timedelta(days=7),
        }
        await db.families.insert_one(family)
        print(f"Created family {family['name']} ({family['_id']})")

    if args.baby:
        baby = await db.babies.find_one({"_id": args.baby, "family_id": family["_id"]})
        if baby is None:
            raise SystemExit("No such baby in that family.")
    else:
        baby = await db.babies.find_one({"family_id": family["_id"]}, sort=[("created_at", 1)])

    if baby is None:
        born = date.today() - timedelta(days=round(args.age_months * DAYS_A_MONTH))
        baby = {
            "_id": new_id(),
            "family_id": family["_id"],
            "name": args.baby_name,
            "nicknames": [],
            "birthdate": born.isoformat(),
            "sex": "female",
            "created_at": utc_now(),
        }
        await db.babies.insert_one(baby)
        print(f"Created baby {baby['name']} ({baby['_id']}), born {born}")

    # Age drives every number below, and the app's own answers, so a baby with no
    # birthdate gets the one this run assumed rather than a silent guess.
    if not baby.get("birthdate"):
        born = (date.today() - timedelta(days=round(args.age_months * DAYS_A_MONTH))).isoformat()
        await db.babies.update_one({"_id": baby["_id"]}, {"$set": {"birthdate": born}})
        baby["birthdate"] = born
        print(f"{baby['name']} had no birthdate; set to {born} (--age-months)")

    return family, baby


def _parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--family", help="family id to seed into")
    target.add_argument("--invite", help="invite code, as shown in the app's Settings")
    target.add_argument("--latest", action="store_true",
                        help="the most recently created family (the one you just onboarded)")
    parser.add_argument("--baby", help="baby id; defaults to the family's first")
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--tz", default="+00:00", help="the caregiver's UTC offset")
    parser.add_argument("--currency", default="USD")
    parser.add_argument("--age-months", type=float, default=5.0,
                        help="used only when the baby has no birthdate")
    parser.add_argument("--seed", type=int, default=7, help="same seed, same week")
    parser.add_argument("--replace", action="store_true",
                        help="delete this baby's records in the window first")
    parser.add_argument("--family-name", default="Seed family")
    parser.add_argument("--baby-name", default="Haein")
    return parser.parse_args(argv)


async def main(argv: Optional[list[str]] = None) -> int:
    args = _parse_args(argv)
    tz = parse_tz(args.tz)
    db = get_db()

    family, baby = await _resolve_baby(db, args)
    now = utc_now()
    window_start = (now.astimezone(tz) - timedelta(days=args.days - 1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )

    existing = await db.events.count_documents(
        {"baby_id": baby["_id"], "time": {"$gte": window_start}}
    )
    if existing and not args.replace:
        print(f"{baby['name']} already has {existing} records in that window. "
              f"Re-run with --replace to overwrite them.")
        return 1
    if existing:
        removed = await db.events.delete_many(
            {"baby_id": baby["_id"], "time": {"$gte": window_start}}
        )
        print(f"Removed {removed.deleted_count} existing records")

    events = build_events(
        family_id=family["_id"],
        baby_id=baby["_id"],
        birthdate=date.fromisoformat(baby["birthdate"]),
        members=family.get("members", []),
        days=args.days,
        tz=tz,
        now=now,
        seed=args.seed,
        currency=args.currency,
    )
    await db.events.insert_many(events)

    counts = Counter(doc["type"] for doc in events)
    print(f"\nSeeded {len(events)} records for {baby['name']} "
          f"over {args.days} days (UTC{args.tz})")
    for type_, count in counts.most_common():
        print(f"  {type_:<14} {count}")
    print(f"\nfamily_id   {family['_id']}")
    print(f"baby_id     {baby['_id']}")
    print(f"invite code {family['invite_code']}")
    return 0


async def _run(argv: Optional[list[str]] = None) -> int:
    # The client binds to the loop that created it, so it has to be closed on that one.
    try:
        return await main(argv)
    finally:
        await close_client()


if __name__ == "__main__":
    sys.exit(asyncio.run(_run()))
