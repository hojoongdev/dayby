"""The two-pass query: a question -> a plan -> a Mongo query the server runs.

The plan-to-Mongo translation is the safety-critical part (the model never writes Mongo),
so _match is tested directly. The mock's planning heuristic is checked too; a real model's
planning and the final answer are proven with the live Gemini test and end-to-end.
"""
import re
from datetime import datetime, timezone

from app.models.events import LlmContext, QueryPlan
from app.providers.llm.mock import MockLLMProvider
from app.query import _match

UTC = timezone.utc


def test_a_type_and_date_range_become_a_scoped_filter():
    plan = QueryPlan(
        type="growth",
        since=datetime(2026, 3, 1, tzinfo=UTC),
        until=datetime(2026, 3, 31, tzinfo=UTC),
    )
    query = _match(plan, "fam1", "baby1")

    assert query["family_id"] == "fam1"
    assert query["baby_id"] == "baby1"
    assert query["type"] == "growth"
    assert query["time"]["$gte"] == datetime(2026, 3, 1, tzinfo=UTC)
    assert query["time"]["$lte"] == datetime(2026, 3, 31, tzinfo=UTC)


def test_no_baby_leaves_the_query_at_the_family():
    query = _match(QueryPlan(type="feeding"), "fam1", None)
    assert "baby_id" not in query
    assert query["family_id"] == "fam1"


def test_contains_matches_several_text_fields():
    query = _match(QueryPlan(contains="hospital"), "fam1", None)
    assert "$or" in query
    fields = [list(clause.keys())[0] for clause in query["$or"]]
    assert "note" in fields
    assert "fields.title" in fields


def test_a_contains_word_is_escaped_not_run_as_a_regex():
    # A question containing regex metacharacters must not become a live pattern.
    query = _match(QueryPlan(contains="a.*b(c"), "fam1", None)
    assert query["$or"][0]["note"]["$regex"] == re.escape("a.*b(c")


def _ctx() -> LlmContext:
    return LlmContext(now=datetime(2026, 7, 20, 12, tzinfo=UTC))


async def test_mock_plans_a_count_for_how_many():
    plan = await MockLLMProvider().plan_query("how many feedings today?", _ctx())
    assert plan.type == "feeding"
    assert plan.aggregate == "count"


async def test_mock_plans_the_last_one():
    plan = await MockLLMProvider().plan_query("when was the last diaper?", _ctx())
    assert plan.type == "diaper"
    assert plan.sort == "desc"
    assert plan.limit == 1


async def test_mock_plans_a_total_volume():
    plan = await MockLLMProvider().plan_query("how much has she fed in total?", _ctx())
    assert plan.type == "feeding"
    assert plan.aggregate == "sum:amount_ml"
