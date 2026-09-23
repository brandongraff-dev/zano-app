"""Pydantic request/response models for the ZANO ML service.

Field names deliberately mirror the Postgres tables in docs/spec.md §13
(`daily_plans`, `goal_events`, `risk_scores`, `nudges`) so Edge Functions can
pass rows through with minimal translation, and so a future real model can
read the same features without an API-shape migration.

NOTE ON STATUS (see docs/spec.md §9): `goal_events` does not have real
production data yet, so every endpoint here is a clearly-labeled heuristic
stub, not a trained model. Each response includes a `model_version` /
`source` field starting with "heuristic_" so callers (and logs) can always
tell stub output from a real model's output later.
"""

from __future__ import annotations

from datetime import date as Date
from enum import Enum
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


# ---------------------------------------------------------------------------
# Shared enums
# ---------------------------------------------------------------------------


class GoalEventKind(str, Enum):
    """Mirrors `goal_events.kind` (spec.md §13)."""

    LOG = "log"
    VERIFY = "verify"
    COMPLETE = "complete"
    MISS = "miss"
    PLAN_B = "plan_b"
    FREEZE = "freeze"


class CoachVoice(str, Enum):
    """Mirrors `users.coach_voice` / spec.md §5.13 coach voices."""

    HYPE = "hype"
    TOUGH_LOVE = "tough_love"
    CHILL = "chill"
    DATA = "data"


class NudgeTimingSlot(str, Enum):
    """One of the 4 timing-slot arms in spec.md §9.3.

    Raw values must match `Core/Sources/Core/Models/Nudge.swift`'s `NudgeTimingSlot` exactly —
    that Swift enum is what actually writes `nudges.arm` (jsonb) rows from the app (spec.md §13),
    and this service's `/nudge` endpoint folds those same rows back in as `ArmOutcome.arm_id`
    history (see `app/nudge_bandit.py`'s `update_posterior`). `AFTERNOON` was previously
    `"four_pm"` here vs. Swift's `afternoon4pm = "afternoon_4pm"` — any real nudge logged by the
    app in the 4 PM slot would fail `update_posterior`'s arm_id lookup (HTTP 422) instead of
    training the bandit. Fixed to match.
    """

    MORNING = "morning"
    PRE_GYM = "pre_gym_window"
    AFTERNOON = "afternoon_4pm"
    EVENING = "evening"


class NudgeFormat(str, Enum):
    """One of the 3 format arms in spec.md §9.3."""

    PUSH = "push"
    WIDGET_COPY = "widget_copy"
    SHIELD_COPY = "shield_copy"


class RiskTier(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


# ---------------------------------------------------------------------------
# POST /plan — Adaptive Goal Engine (spec.md §9.1)
# ---------------------------------------------------------------------------


class DailyCompletion(BaseModel):
    """One day of history for a single goal, used to compute the 7/28-day rate.

    Deliberately minimal — this is the subset of a `goal_events` day-summary
    the v1 rules engine needs, not the full row shape.
    """

    date: Date
    completed: bool
    was_plan_b: bool = False
    was_freeze: bool = False


class PlanRequest(BaseModel):
    """Input for the v1 rules-based Adaptive Goal Engine (spec.md §9.1).

    `last_28_days` should be ordered oldest -> newest and may contain fewer
    than 28 entries for a new goal (cold start); the engine treats missing
    history as "no signal yet" and returns the goal's current target
    unchanged rather than guessing a step.
    """

    user_id: UUID
    goal_id: UUID
    goal_type: str = Field(..., description="e.g. 'workout', 'protein', 'water', 'focus'")
    current_target_value: float = Field(..., gt=0)
    unit: str = Field(..., description="e.g. 'minutes', 'grams', 'ml', 'sessions'")
    difficulty_step: int = Field(
        default=0, description="Current step offset from the goal's baseline target; can go negative."
    )
    current_streak: int = Field(default=0, ge=0)
    plan_date: Date
    last_28_days: list[DailyCompletion] = Field(default_factory=list)
    last_difficulty_change_date: Optional[Date] = Field(
        default=None,
        description=(
            "Date the difficulty step last changed. This service is stateless, so the caller "
            "(Edge Function, which owns `daily_plans`) supplies this to let the engine honor "
            "spec.md §9.1's 'never change more than one step per week' rule."
        ),
    )

    @field_validator("last_28_days")
    @classmethod
    def _sorted_oldest_first(cls, v: list[DailyCompletion]) -> list[DailyCompletion]:
        return sorted(v, key=lambda d: d.date)


class PlanResponse(BaseModel):
    """A single `daily_plans` row's ML-owned fields (spec.md §13)."""

    goal_id: UUID
    date: Date
    planned_value: float
    difficulty_step: int
    plan_b_value: Optional[float] = Field(
        default=None, description="Lower-effort fallback value offered when risk is high; see §9.2."
    )
    source: str = "heuristic_v1"
    rationale: str = Field(..., description="Short, non-user-facing explanation for logs/debugging.")


# ---------------------------------------------------------------------------
# POST /risk — Slip Prediction (spec.md §9.2)
# ---------------------------------------------------------------------------


class RiskRequest(BaseModel):
    """Feature vector for slip-risk scoring (spec.md §9.2).

    All fields beyond `user_id`/`date` are optional: the real model will
    need most of them, but the current heuristic stub only reads a few and
    treats the rest as forward-compatible plumbing.
    """

    user_id: UUID
    date: Date
    day_of_week: Optional[int] = Field(default=None, ge=0, le=6, description="0=Monday .. 6=Sunday")
    days_since_last_miss: Optional[int] = Field(default=None, ge=0)
    streak_length: int = Field(default=0, ge=0)
    yesterday_completed: Optional[bool] = None
    sleep_hours: Optional[float] = Field(default=None, ge=0, le=24)
    calendar_density: Optional[float] = Field(
        default=None, ge=0, le=1, description="0..1, opt-in Calendar access only"
    )
    weather: Optional[str] = None
    travel_flag: bool = False
    hour_of_first_app_open: Optional[int] = Field(default=None, ge=0, le=23)


class RiskResponse(BaseModel):
    """Mirrors `risk_scores` (user_id, date, p_miss, model_version) — spec.md §13."""

    user_id: UUID
    date: Date
    p_miss: float = Field(..., ge=0, le=1)
    risk_tier: RiskTier
    model_version: str = "heuristic_baseline_v1"
    offer_plan_b: bool = Field(
        ..., description="True when p_miss crosses the action threshold; spec.md §9.2 'risk > threshold at 9 AM'."
    )


# ---------------------------------------------------------------------------
# POST /nudge — Nudge Optimizer (spec.md §9.3)
# ---------------------------------------------------------------------------


class NudgeOutcome(BaseModel):
    """One past *delivered* nudge's logged outcome for this user — the bandit's training signal.

    Mirrors the `nudges` table (spec.md §13):
    `nudges (id, user_id, ts, arm jsonb, delivered, acted_within_3h)`. Only delivered nudges should
    be included; an undelivered one was never shown, so it has no reward either way.
    """

    arm_id: str = Field(
        ...,
        description="Must be one of the 48 canonical arm ids (see app/nudge_bandit.ALL_ARMS); "
        "unknown ids fail the request with a 422 rather than being silently dropped.",
    )
    rewarded: bool = Field(
        ..., description="spec.md §9.3 reward: goal completed within 3 hours of this nudge."
    )


class NudgeRequest(BaseModel):
    """Context for picking a nudge arm (spec.md §9.3).

    `nudges_sent_today` lets the caller enforce the 2/day cap even though
    the endpoint also refuses to recommend a 3rd nudge itself, defense in depth
    since the cap is a product-safety rule (spec.md §8/§9.3), not a nicety.

    `history` is this user's past delivered-nudge outcomes (any order) — the bandit's "per-user
    update" input (spec.md §9.3). This service is stateless (app/main.py's module docstring), so
    the caller (an Edge Function reading `nudges`) resends the full history on every call; nothing
    is persisted here. An empty list is the population-prior cold start: a brand-new user with no
    nudge history yet.
    """

    user_id: UUID
    date: Date
    coach_voice: Optional[CoachVoice] = None
    current_hour: Optional[int] = Field(default=None, ge=0, le=23)
    nudges_sent_today: int = Field(default=0, ge=0)
    p_miss: Optional[float] = Field(
        default=None, ge=0, le=1, description="Optional /risk output, reused so callers don't recompute it."
    )
    history: list[NudgeOutcome] = Field(
        default_factory=list,
        description="This user's past delivered-nudge outcomes; see NudgeOutcome. Empty -> "
        "population-prior cold start (spec.md §9.3).",
    )


class NudgeResponse(BaseModel):
    """Mirrors the arm chosen for a `nudges` row (`arm jsonb`) — spec.md §13."""

    user_id: UUID
    tone: CoachVoice
    timing_slot: NudgeTimingSlot
    format: NudgeFormat
    arm_id: str = Field(..., description="Stable id for this tone/slot/format combo, for bandit bookkeeping later.")
    should_send: bool = Field(..., description="False when the 2/day cap (spec.md §9.3) has already been hit.")
    model_version: str = "bandit_thompson_v1"
    posterior_mean: float = Field(
        ...,
        ge=0,
        le=1,
        description="This arm's E[reward] under the user's current Beta posterior (population "
        "prior + history) — the value Thompson sampling drew its winning sample from.",
    )
    is_cold_start: bool = Field(
        ...,
        description="True when this user had zero logged nudge history (pure population prior, "
        "spec.md §9.3), false once at least one past outcome informed the posterior.",
    )
