"""ZANO ML Service — FastAPI skeleton.

Implements spec.md §9.9: "Python ML service (FastAPI) exposes /plan, /risk,
/nudge endpoints; Edge Functions call it."

STATUS: `/plan` and `/risk` are deliberately simple, clearly-labeled heuristic stubs (see each
function's docstring), not trained models — spec.md §9.1/§9.2 describe the real v1/v2 approach
(rules -> bandit, logistic regression -> LightGBM), which needs `goal_events` production data that
does not exist yet, so those two follow spec.md §9's opening line ("Start rules-based, replace with
models as `goal_events` grows") and label every response via a `source`/`model_version` field
prefixed "heuristic_". `/nudge` (spec.md §9.3) is different: it's a real Thompson-sampling
contextual bandit (`app/nudge_bandit.py`), not a heuristic — see that module and `nudge()` below for
why a bandit needs no `goal_events` history to start from (population prior) the way `/risk`'s
model does. Its `model_version` is `"bandit_thompson_v1"`, not `"heuristic_..."`.

This service is stateless: it does no persistence and holds no DB
connection. It is a pure function of each request's payload. Supabase Edge
Functions (spec.md §11) own reading/writing `daily_plans`, `risk_scores`,
and `nudges` and are expected to pass in whatever history each endpoint
needs and to persist the response.
"""

from __future__ import annotations

from datetime import date as Date
from typing import Optional
from uuid import UUID

from fastapi import FastAPI, HTTPException

from app import nudge_bandit
from app.models import (
    NudgeOutcome,
    NudgeRequest,
    NudgeResponse,
    NudgeTimingSlot,
    PlanRequest,
    PlanResponse,
    RiskRequest,
    RiskResponse,
    RiskTier,
)

app = FastAPI(
    title="ZANO ML Service",
    description=(
        "Adaptive plan, slip-risk, and nudge-selection endpoints for the ZANO app "
        "(docs/spec.md §9). Heuristic stubs until goal_events has enough data to train on."
    ),
    version="0.1.0",
)


# ---------------------------------------------------------------------------
# Tunables for the v1 heuristics — named and documented, not magic numbers.
# See docs/spec.md §9.1/§9.2/§9.3 for where each number comes from.
# ---------------------------------------------------------------------------

# §9.1: "target completion rate 75-85%"
PLAN_TARGET_RATE_LOW = 0.75
PLAN_TARGET_RATE_HIGH = 0.85
# §9.1: "If 7-day rate < 60% -> lower the daily bar one step"
PLAN_LOWER_THRESHOLD = 0.60
PLAN_LOWER_WINDOW_DAYS = 7
# §9.1: "If > 90% for 10 days -> raise one step"
PLAN_RAISE_THRESHOLD = 0.90
PLAN_RAISE_WINDOW_DAYS = 10
# §9.1: "Never change more than one step per week."
PLAN_MIN_DAYS_BETWEEN_CHANGES = 7

# §9.2: cold-start baseline miss probability, population-level, before any
# per-user model exists. This is intentionally a single constant for now —
# see RiskResponse docstring / knownIssues.
RISK_BASELINE_P_MISS = 0.22
# §9.2: "risk > threshold at 9 AM -> offer Plan B"
RISK_ACTION_THRESHOLD = 0.5
RISK_LOW_UPPER = 0.33
RISK_MEDIUM_UPPER = 0.60

# §9.3: "Respect the 2/day cap."
NUDGE_DAILY_CAP = 2


@app.get("/health")
def health() -> dict[str, str]:
    """Liveness check — not part of the spec, but standard for a deployed service."""
    return {"status": "ok"}


@app.post("/plan", response_model=PlanResponse)
def plan(req: PlanRequest) -> PlanResponse:
    """Adaptive Goal Engine v1 — rules only (spec.md §9.1).

    HEURISTIC STUB: this is exactly the v1 rules engine spec.md §9.1 describes,
    not a placeholder for it — v2 (contextual bandit, Thompson sampling) is
    the future upgrade once there's enough `goal_events` history per user.

    Rule, in order:
    1. If fewer than `PLAN_LOWER_WINDOW_DAYS` days of history exist, there's no
       signal yet: return the current target unchanged.
    2. If a difficulty change happened within the last
       `PLAN_MIN_DAYS_BETWEEN_CHANGES` days, don't change again this week.
    3. If the trailing 7-day completion rate is below 60%, lower one step.
    4. Else if the trailing 10-day completion rate is above 90% (and at least
       10 days of history exist), raise one step.
    5. Otherwise, hold steady — the user is already inside the 75-85% target band.
    """
    history = req.last_28_days  # already sorted oldest -> newest by the model validator

    if len(history) < PLAN_LOWER_WINDOW_DAYS:
        return PlanResponse(
            goal_id=req.goal_id,
            date=req.plan_date,
            planned_value=req.current_target_value,
            difficulty_step=req.difficulty_step,
            plan_b_value=None,
            source="heuristic_v1",
            rationale=f"Only {len(history)} day(s) of history; holding steady until {PLAN_LOWER_WINDOW_DAYS}+ days exist.",
        )

    days_since_change: Optional[int] = None
    if req.last_difficulty_change_date is not None:
        days_since_change = (req.plan_date - req.last_difficulty_change_date).days
        if 0 <= days_since_change < PLAN_MIN_DAYS_BETWEEN_CHANGES:
            return PlanResponse(
                goal_id=req.goal_id,
                date=req.plan_date,
                planned_value=req.current_target_value,
                difficulty_step=req.difficulty_step,
                plan_b_value=_plan_b_value(req.current_target_value),
                source="heuristic_v1",
                rationale=(
                    f"Difficulty changed {days_since_change} day(s) ago; "
                    f"holding until {PLAN_MIN_DAYS_BETWEEN_CHANGES} days have passed."
                ),
            )

    last_7 = history[-PLAN_LOWER_WINDOW_DAYS:]
    rate_7 = sum(1 for d in last_7 if d.completed) / len(last_7)

    if rate_7 < PLAN_LOWER_THRESHOLD:
        new_step = req.difficulty_step - 1
        new_value = _step_target_value(req.current_target_value, new_step - req.difficulty_step)
        return PlanResponse(
            goal_id=req.goal_id,
            date=req.plan_date,
            planned_value=new_value,
            difficulty_step=new_step,
            plan_b_value=_plan_b_value(new_value),
            source="heuristic_v1",
            rationale=f"7-day completion rate {rate_7:.0%} < {PLAN_LOWER_THRESHOLD:.0%}; lowering one step.",
        )

    if len(history) >= PLAN_RAISE_WINDOW_DAYS:
        last_10 = history[-PLAN_RAISE_WINDOW_DAYS:]
        rate_10 = sum(1 for d in last_10 if d.completed) / len(last_10)
        if rate_10 > PLAN_RAISE_THRESHOLD:
            new_step = req.difficulty_step + 1
            new_value = _step_target_value(req.current_target_value, new_step - req.difficulty_step)
            return PlanResponse(
                goal_id=req.goal_id,
                date=req.plan_date,
                planned_value=new_value,
                difficulty_step=new_step,
                plan_b_value=_plan_b_value(new_value),
                source="heuristic_v1",
                rationale=f"10-day completion rate {rate_10:.0%} > {PLAN_RAISE_THRESHOLD:.0%}; raising one step.",
            )

    return PlanResponse(
        goal_id=req.goal_id,
        date=req.plan_date,
        planned_value=req.current_target_value,
        difficulty_step=req.difficulty_step,
        plan_b_value=_plan_b_value(req.current_target_value),
        source="heuristic_v1",
        rationale=f"7-day rate {rate_7:.0%} within target band ({PLAN_TARGET_RATE_LOW:.0%}-{PLAN_TARGET_RATE_HIGH:.0%}); holding.",
    )


def _step_target_value(current_value: float, step_delta: int) -> float:
    """Move `current_value` by one 10%-of-current step per unit of `step_delta`.

    This is a simple, additive-only (spec.md "additive goals only" product
    rule, §24) step function: it only ever scales an existing positive
    target up or down, never introduces a restrictive/negative goal type.
    Floors at a small positive value so a goal never steps down to zero.
    """
    step_size = max(current_value * 0.10, 1.0)
    new_value = current_value + step_delta * step_size
    return round(max(new_value, step_size), 1)


def _plan_b_value(target_value: float) -> float:
    """Lower-effort fallback value, offered on high slip risk (spec.md §9.2).

    Heuristic: 50% of the current target, same additive-only spirit as
    `_step_target_value` — Plan B is a smaller version of the same goal,
    never a different, restrictive one.
    """
    return round(max(target_value * 0.5, 1.0), 1)


@app.post("/risk", response_model=RiskResponse)
def risk(req: RiskRequest) -> RiskResponse:
    """Slip Prediction v0 — fixed baseline, not yet a trained model (spec.md §9.2).

    HEURISTIC STUB, explicitly simpler than the spec's own cold-start plan
    (logistic regression on onboarding answers + population priors): with no
    `goal_events` data to fit even a logistic regression on yet, this
    returns a single fixed population baseline (`RISK_BASELINE_P_MISS`)
    nudged by a few of the request's own signals as small, clearly-labeled
    adjustments — NOT a calibrated probability. Treat `p_miss` as a rough
    ranking signal only until a real model replaces this.
    """
    p = RISK_BASELINE_P_MISS

    # Small, transparent adjustments — each one independently justified by
    # spec.md §9.2's feature list, not fit to any data.
    if req.yesterday_completed is False:
        p += 0.15
    elif req.yesterday_completed is True:
        p -= 0.05

    if req.streak_length >= 7:
        p -= 0.05
    elif req.streak_length == 0:
        p += 0.05

    if req.days_since_last_miss is not None and req.days_since_last_miss <= 1:
        p += 0.05

    if req.sleep_hours is not None and req.sleep_hours < 6:
        p += 0.05

    if req.calendar_density is not None and req.calendar_density > 0.7:
        p += 0.05

    if req.travel_flag:
        p += 0.05

    p_miss = round(min(max(p, 0.01), 0.99), 3)

    if p_miss <= RISK_LOW_UPPER:
        tier = RiskTier.LOW
    elif p_miss <= RISK_MEDIUM_UPPER:
        tier = RiskTier.MEDIUM
    else:
        tier = RiskTier.HIGH

    return RiskResponse(
        user_id=req.user_id,
        date=req.date,
        p_miss=p_miss,
        risk_tier=tier,
        model_version="heuristic_baseline_v1",
        offer_plan_b=p_miss > RISK_ACTION_THRESHOLD,
    )


@app.post("/nudge", response_model=NudgeResponse)
def nudge(req: NudgeRequest) -> NudgeResponse:
    """Nudge Optimizer — per-user Thompson-sampling contextual bandit (spec.md §9.3).

    Real bandit (see `app/nudge_bandit.py`), not a heuristic stub: arms are the 4 tone x 4 timing
    slot x 3 format = 48 combinations spec.md §9.3 defines. Each arm's reward ("goal completed
    within 3 hours of nudge") is modeled Beta-Bernoulli; every user starts from the uniform
    population prior (`nudge_bandit.population_prior`) and, once `req.history` carries logged
    outcomes for this user (mirroring the `nudges` table, spec.md §13), that history is folded onto
    the prior (`nudge_bandit.update_posterior`) before Thompson sampling draws the arm to serve next
    (`nudge_bandit.select_arm`). This service stays stateless like `/plan` and `/risk` (module
    docstring): the caller resends the full per-user history every call; nothing is persisted here.

    Context narrows the 48-arm space before sampling:
    - `coach_voice`, if given, fixes the tone — that's a product setting the user picked (spec
      §5.13), not something the bandit should override.
    - `current_hour`, if given, fixes the timing slot via `_slot_for_hour`.
    Format is always left fully to the bandit. Any dimension left unconstrained is sampled from the
    user's posterior across all its values.

    The 2/day cap (`NUDGE_DAILY_CAP`) is still enforced here directly, independent of the bandit, as
    a defense-in-depth product-safety check (spec.md §9.3, §8) — `should_send` goes false at the cap
    even though an arm is still chosen and returned for logging/preview purposes.
    """
    should_send = req.nudges_sent_today < NUDGE_DAILY_CAP

    try:
        history = [
            nudge_bandit.ArmOutcome(arm_id=outcome.arm_id, rewarded=outcome.rewarded)
            for outcome in req.history
        ]
        arm, posterior = nudge_bandit.thompson_sample_arm(
            history,
            tone=req.coach_voice,
            timing_slot=_slot_for_hour(req.current_hour),
            seed=_nudge_seed(req.user_id, req.date, req.current_hour, req.history),
        )
    except ValueError as exc:
        # Only reachable via an unknown arm_id in req.history (nudge_bandit.update_posterior) —
        # malformed history should fail loudly rather than silently mis-crediting an arm.
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    arm_posterior = posterior[arm.arm_id]

    return NudgeResponse(
        user_id=req.user_id,
        tone=arm.tone,
        timing_slot=arm.timing_slot,
        format=arm.format,
        arm_id=arm.arm_id,
        should_send=should_send,
        model_version="bandit_thompson_v1",
        posterior_mean=round(arm_posterior.mean, 4),
        is_cold_start=len(req.history) == 0,
    )


def _nudge_seed(user_id: UUID, date: Date, current_hour: Optional[int], history: list[NudgeOutcome]) -> int:
    """Deterministic RNG seed for `/nudge`'s Thompson sample, derived from every input that affects
    the pick: (user, date, hour, history).

    Real exploration should vary sample-to-sample across genuinely different situations, which this
    still does — different user/date/hour/history all change the seed. What it buys instead is
    reproducibility for the *same* inputs (repeat calls, tests, replay/debugging) without this
    stateless service needing to remember anything, the same "reproducible pure function of the
    request" property `/plan` and `/risk` already have. Hashes the key with a fixed, simple
    algorithm (not Python's salted built-in `hash()`, which is process-random) so it's stable across
    runs and interpreters.
    """
    key = f"{user_id}:{date.isoformat()}:{current_hour}:{len(history)}".encode()
    for outcome in history:
        key += f":{outcome.arm_id}:{int(outcome.rewarded)}".encode()
    digest = 0
    for byte in key:
        digest = (digest * 31 + byte) % 2_147_483_647
    return digest


def _slot_for_hour(hour: Optional[int]) -> Optional[NudgeTimingSlot]:
    """Map the caller's current hour to a timing slot when it's provided.

    Rough, documented boundaries only; not a scheduling authority — the
    Edge Function decides when nudges actually fire.
    """
    if hour is None:
        return None
    if 5 <= hour < 11:
        return NudgeTimingSlot.MORNING
    if 11 <= hour < 16:
        return NudgeTimingSlot.PRE_GYM
    if 16 <= hour < 18:
        return NudgeTimingSlot.AFTERNOON
    return NudgeTimingSlot.EVENING
