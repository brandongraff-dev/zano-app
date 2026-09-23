"""Tests for the ZANO ML service skeleton (docs/spec.md §9.9).

Exercises the three endpoints through FastAPI's TestClient (real HTTP-shaped
requests against the app object, no mocking of FastAPI/pydantic internals).
These pin the *current heuristic stub's* behavior, documented in
app/main.py's docstrings and cited by §9.1/§9.2/§9.3 below — when a real
model replaces a stub, these tests should be replaced too, not patched to
keep passing.
"""

from __future__ import annotations

from datetime import date, timedelta
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _uuid() -> str:
    return str(uuid4())


def _history(pattern: list[bool], start: date) -> list[dict]:
    """Build a `last_28_days`-shaped list from oldest -> newest completion booleans."""
    return [
        {"date": (start + timedelta(days=i)).isoformat(), "completed": completed}
        for i, completed in enumerate(pattern)
    ]


def test_health() -> None:
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


# ---------------------------------------------------------------------------
# /plan — spec.md §9.1
# ---------------------------------------------------------------------------


def test_plan_holds_steady_with_insufficient_history() -> None:
    """Fewer than 7 days of history -> no change (rule 1 in app/main.py:plan)."""
    body = {
        "user_id": _uuid(),
        "goal_id": _uuid(),
        "goal_type": "workout",
        "current_target_value": 30,
        "unit": "minutes",
        "difficulty_step": 0,
        "current_streak": 2,
        "plan_date": "2026-09-22",
        "last_28_days": _history([True, True], start=date(2026, 9, 20)),
    }
    resp = client.post("/plan", json=body)
    assert resp.status_code == 200
    data = resp.json()
    assert data["planned_value"] == 30
    assert data["difficulty_step"] == 0
    assert data["source"] == "heuristic_v1"


def test_plan_lowers_one_step_below_60_percent_7day_rate() -> None:
    """7-day rate < 60% -> lower one step (spec.md §9.1)."""
    # 2/7 completed = ~29% < 60%.
    pattern = [True, False, False, True, False, False, False]
    body = {
        "user_id": _uuid(),
        "goal_id": _uuid(),
        "goal_type": "protein",
        "current_target_value": 100,
        "unit": "grams",
        "difficulty_step": 0,
        "current_streak": 0,
        "plan_date": "2026-09-22",
        "last_28_days": _history(pattern, start=date(2026, 9, 15)),
    }
    resp = client.post("/plan", json=body)
    assert resp.status_code == 200
    data = resp.json()
    assert data["difficulty_step"] == -1
    assert data["planned_value"] < 100
    assert "lowering" in data["rationale"].lower()


def test_plan_raises_one_step_above_90_percent_10day_rate() -> None:
    """10-day rate > 90% -> raise one step (spec.md §9.1)."""
    pattern = [True] * 10
    body = {
        "user_id": _uuid(),
        "goal_id": _uuid(),
        "goal_type": "focus",
        "current_target_value": 25,
        "unit": "minutes",
        "difficulty_step": 0,
        "current_streak": 10,
        "plan_date": "2026-09-22",
        "last_28_days": _history(pattern, start=date(2026, 9, 12)),
    }
    resp = client.post("/plan", json=body)
    assert resp.status_code == 200
    data = resp.json()
    assert data["difficulty_step"] == 1
    assert data["planned_value"] > 25


def test_plan_respects_one_step_per_week_cap() -> None:
    """A difficulty change within the last 7 days blocks another change (spec.md §9.1)."""
    pattern = [True] * 10
    body = {
        "user_id": _uuid(),
        "goal_id": _uuid(),
        "goal_type": "focus",
        "current_target_value": 25,
        "unit": "minutes",
        "difficulty_step": 0,
        "current_streak": 10,
        "plan_date": "2026-09-22",
        "last_28_days": _history(pattern, start=date(2026, 9, 12)),
        "last_difficulty_change_date": "2026-09-20",
    }
    resp = client.post("/plan", json=body)
    assert resp.status_code == 200
    data = resp.json()
    assert data["difficulty_step"] == 0
    assert "holding" in data["rationale"].lower()


def test_plan_never_returns_a_restrictive_negative_target() -> None:
    """Additive-goals-only product rule (spec.md §24): planned_value stays positive."""
    pattern = [False] * 7
    body = {
        "user_id": _uuid(),
        "goal_id": _uuid(),
        "goal_type": "water",
        "current_target_value": 1,
        "unit": "liters",
        "difficulty_step": 0,
        "current_streak": 0,
        "plan_date": "2026-09-22",
        "last_28_days": _history(pattern, start=date(2026, 9, 15)),
    }
    resp = client.post("/plan", json=body)
    assert resp.status_code == 200
    assert resp.json()["planned_value"] > 0


# ---------------------------------------------------------------------------
# /risk — spec.md §9.2
# ---------------------------------------------------------------------------


def test_risk_returns_baseline_shape() -> None:
    body = {"user_id": _uuid(), "date": "2026-09-22"}
    resp = client.post("/risk", json=body)
    assert resp.status_code == 200
    data = resp.json()
    assert 0.0 <= data["p_miss"] <= 1.0
    assert data["model_version"] == "heuristic_baseline_v1"
    assert data["risk_tier"] in {"low", "medium", "high"}
    assert isinstance(data["offer_plan_b"], bool)


def test_risk_increases_when_yesterday_missed_and_streak_is_zero() -> None:
    low_risk_body = {
        "user_id": _uuid(),
        "date": "2026-09-22",
        "yesterday_completed": True,
        "streak_length": 10,
    }
    high_risk_body = {
        "user_id": _uuid(),
        "date": "2026-09-22",
        "yesterday_completed": False,
        "streak_length": 0,
        "days_since_last_miss": 0,
    }
    low_resp = client.post("/risk", json=low_risk_body).json()
    high_resp = client.post("/risk", json=high_risk_body).json()
    assert high_resp["p_miss"] > low_resp["p_miss"]


def test_risk_offers_plan_b_above_threshold() -> None:
    body = {
        "user_id": _uuid(),
        "date": "2026-09-22",
        "yesterday_completed": False,
        "streak_length": 0,
        "days_since_last_miss": 0,
        "sleep_hours": 4,
        "calendar_density": 0.9,
        "travel_flag": True,
    }
    resp = client.post("/risk", json=body)
    data = resp.json()
    assert data["p_miss"] > 0.5
    assert data["offer_plan_b"] is True
    assert data["risk_tier"] == "high"


# ---------------------------------------------------------------------------
# /nudge — spec.md §9.3
# ---------------------------------------------------------------------------


def test_nudge_returns_a_valid_arm() -> None:
    body = {"user_id": _uuid(), "date": "2026-09-22", "current_hour": 8}
    resp = client.post("/nudge", json=body)
    assert resp.status_code == 200
    data = resp.json()
    assert data["tone"] in {"hype", "tough_love", "chill", "data"}
    assert data["timing_slot"] == "morning"  # hour=8 maps to morning
    assert data["format"] in {"push", "widget_copy", "shield_copy"}
    assert data["should_send"] is True
    assert data["arm_id"] == f"{data['tone']}:{data['timing_slot']}:{data['format']}"
    assert data["model_version"] == "bandit_thompson_v1"


def test_nudge_cold_start_has_population_prior_mean_and_is_cold_start_true() -> None:
    """spec.md §9.3: 'Per-user bandit with population prior.' No history -> Beta(1,1) -> mean 0.5,
    and the response says so explicitly via is_cold_start."""
    body = {"user_id": _uuid(), "date": "2026-09-22"}
    resp = client.post("/nudge", json=body)
    data = resp.json()
    assert data["is_cold_start"] is True
    assert data["posterior_mean"] == pytest.approx(0.5)


def test_nudge_with_history_updates_posterior_mean_for_the_chosen_arm() -> None:
    """The response's posterior_mean must always equal alpha/(alpha+beta) for a Beta(1,1) prior
    folded with however many of this user's history entries belong to the arm actually returned —
    true no matter which of the context-eligible arms Thompson sampling ends up picking."""
    uid = _uuid()
    trained_arm_id = "hype:morning:push"
    history = [{"arm_id": trained_arm_id, "rewarded": True} for _ in range(10)]
    body = {
        "user_id": uid,
        "date": "2026-09-22",
        "current_hour": 8,  # forces timing_slot=morning
        "coach_voice": "hype",  # forces tone=hype; format stays bandit-controlled
        "history": history,
    }
    resp = client.post("/nudge", json=body)
    assert resp.status_code == 200
    data = resp.json()
    assert data["is_cold_start"] is False
    assert data["tone"] == "hype"
    assert data["timing_slot"] == "morning"

    rewards = sum(1 for h in history if h["arm_id"] == data["arm_id"] and h["rewarded"])
    misses = sum(1 for h in history if h["arm_id"] == data["arm_id"] and not h["rewarded"])
    expected_mean = (1 + rewards) / (1 + rewards + 1 + misses)
    assert data["posterior_mean"] == pytest.approx(expected_mean, abs=1e-4)


def test_nudge_rejects_unknown_arm_id_in_history_with_422() -> None:
    body = {
        "user_id": _uuid(),
        "date": "2026-09-22",
        "history": [{"arm_id": "not_a_real_arm", "rewarded": True}],
    }
    resp = client.post("/nudge", json=body)
    assert resp.status_code == 422


def test_nudge_respects_daily_cap() -> None:
    """2/day cap (spec.md §9.3) — should_send flips false at the cap."""
    body = {"user_id": _uuid(), "date": "2026-09-22", "nudges_sent_today": 2}
    resp = client.post("/nudge", json=body)
    assert resp.json()["should_send"] is False


def test_nudge_honors_explicit_coach_voice() -> None:
    body = {"user_id": _uuid(), "date": "2026-09-22", "coach_voice": "tough_love"}
    resp = client.post("/nudge", json=body)
    assert resp.json()["tone"] == "tough_love"


def test_nudge_is_deterministic_for_same_user_and_date() -> None:
    uid = _uuid()
    body = {"user_id": uid, "date": "2026-09-22"}
    first = client.post("/nudge", json=body).json()
    second = client.post("/nudge", json=body).json()
    assert first["arm_id"] == second["arm_id"]


def test_validation_error_returns_422() -> None:
    """Pydantic validation (e.g. day_of_week out of 0-6 range) surfaces as a 422."""
    resp = client.post("/risk", json={"user_id": _uuid(), "date": "2026-09-22", "day_of_week": 9})
    assert resp.status_code == 422
