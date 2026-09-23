"""Nudge Optimizer — Thompson-sampling contextual bandit (docs/spec.md §9.3).

    "### 9.3 Nudge Optimizer
    - Arms: tone (4) x timing slot (morning / pre-gym window / 4 PM / evening) x format
      (push / widget copy / shield copy).
    - Reward: goal completed within 3 hours of nudge.
    - Per-user bandit with population prior. Respect the 2/day cap." — spec.md §9.3

This module is the real bandit, not a stub: a Beta-Bernoulli Thompson-sampling multi-armed bandit
over the 4 (tone) x 4 (timing slot) x 3 (format) = 48-arm space spec.md §9.3 defines. `app/main.py`'s
`/nudge` endpoint is the only caller; this module does no I/O, holds no state, and knows nothing
about FastAPI/HTTP, so it can be unit-tested directly (tests/test_nudge_bandit.py) without spinning
up the app.

Why Beta-Bernoulli Thompson sampling: the reward (spec §9.3: "goal completed within 3 hours of
nudge") is binary per nudge, which is exactly the Bernoulli-reward setting Beta-Bernoulli Thompson
sampling is built for — the Beta distribution is the conjugate prior for a Bernoulli likelihood, so
"population prior + this user's (arm, reward) history" is a single closed-form posterior update
(`update_posterior`) with no numerical fitting needed, and drawing one sample per arm from its
posterior and picking the highest (`select_arm`) is the whole algorithm. No extra dependency: only
`random.betavariate`, already in the standard library.

Why this satisfies "per-user bandit with population prior": every arm starts at the *population*
prior (`population_prior`, a uniform Beta(1,1) — "reasonable defaults" per-arm, maximally uncertain
so a brand-new user's first few nudges still explore the full arm space rather than being biased by
a guessed success rate). As a user's own logged nudge outcomes come in, `update_posterior` folds
them onto that same prior, so a user with history is sampled from *their own* posterior while a
user with none still gets sensible, unbiased-random behavior — cold start handled by construction,
not a special-cased branch.

Statelessness: like every other endpoint in this service (see app/main.py's module docstring), this
module holds no per-user state of its own. The caller (app/main.py's `/nudge` endpoint) re-derives
each user's posterior from scratch on every call by passing that user's full outcome history
(mirroring the `nudges` Postgres table, spec.md §13) into `update_posterior`; nothing here persists
between calls. That's intentionally the same "caller supplies history, service is a pure function of
the request" shape as `/plan`'s `last_28_days`.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from typing import Iterable, Mapping, Optional, Sequence

from app.models import CoachVoice, NudgeFormat, NudgeTimingSlot

# ---------------------------------------------------------------------------
# Arm space — spec.md §9.3: "tone (4) x timing slot (4) x format (3) = 48 arms".
# ---------------------------------------------------------------------------

TONES: tuple[CoachVoice, ...] = (
    CoachVoice.HYPE,
    CoachVoice.TOUGH_LOVE,
    CoachVoice.CHILL,
    CoachVoice.DATA,
)
TIMING_SLOTS: tuple[NudgeTimingSlot, ...] = (
    NudgeTimingSlot.MORNING,
    NudgeTimingSlot.PRE_GYM,
    NudgeTimingSlot.AFTERNOON,  # "4 PM" in spec prose; NudgeTimingSlot.AFTERNOON in code (app/models.py).
    NudgeTimingSlot.EVENING,
)
FORMATS: tuple[NudgeFormat, ...] = (
    NudgeFormat.PUSH,
    NudgeFormat.WIDGET_COPY,
    NudgeFormat.SHIELD_COPY,
)


@dataclass(frozen=True, slots=True)
class Arm:
    """One point in the 48-arm space: a (tone, timing slot, format) combination."""

    tone: CoachVoice
    timing_slot: NudgeTimingSlot
    format: NudgeFormat

    @property
    def arm_id(self) -> str:
        """Stable id, same shape as app/main.py's pre-bandit heuristic used
        (`f"{tone}:{slot}:{format}"`) so logged `nudges.arm` rows and any
        historical arm_ids from before this module existed still parse."""
        return f"{self.tone.value}:{self.timing_slot.value}:{self.format.value}"


ALL_ARMS: tuple[Arm, ...] = tuple(
    Arm(tone=tone, timing_slot=slot, format=fmt)
    for tone in TONES
    for slot in TIMING_SLOTS
    for fmt in FORMATS
)

assert len(ALL_ARMS) == 48, "spec.md §9.3: 4 tones x 4 timing slots x 3 formats = 48 arms"
assert len({arm.arm_id for arm in ALL_ARMS}) == 48, "arm_ids must be unique"

ARMS_BY_ID: dict[str, Arm] = {arm.arm_id: arm for arm in ALL_ARMS}


# ---------------------------------------------------------------------------
# Population prior — cold start (spec.md §9.3: "Per-user bandit with population prior").
# ---------------------------------------------------------------------------

# Beta(1, 1) is the uniform distribution on [0, 1]: "I have no idea this arm's success rate is
# anything but coin-flip-uncertain." That's the deliberately-chosen "reasonable default" cold-start
# prior — not fit to any data (there is no `nudges` production history yet, same situation
# app/features.py's POPULATION_PRIOR_P_MISS / app/main.py's RISK_BASELINE_P_MISS document for the
# other two endpoints), and it lets the bandit explore every arm roughly evenly for a brand-new
# user instead of being steered by a guessed number. Once a population-level nudges dataset exists,
# these can be replaced by each arm's observed population mean without changing this module's shape.
POPULATION_PRIOR_ALPHA = 1.0
POPULATION_PRIOR_BETA = 1.0


@dataclass(frozen=True, slots=True)
class ArmOutcome:
    """One past *delivered* nudge's logged outcome for this user.

    Mirrors the `nudges` table (spec.md §13):
    `nudges (id, user_id, ts, arm jsonb, delivered, acted_within_3h)`.
    Callers should only include delivered nudges — an undelivered nudge was never shown to the
    user, so it carries no reward signal in either direction and would only bias the posterior
    toward whatever arm happened not to fire.
    """

    arm_id: str
    rewarded: bool  # spec §9.3: "goal completed within 3 hours of nudge" == `nudges.acted_within_3h`.


@dataclass(frozen=True, slots=True)
class ArmPosterior:
    """This user's current Beta(alpha, beta) posterior for one arm's reward probability."""

    arm_id: str
    alpha: float
    beta: float

    @property
    def mean(self) -> float:
        """Posterior mean success rate — E[Beta(alpha, beta)] = alpha / (alpha + beta)."""
        return self.alpha / (self.alpha + self.beta)

    @property
    def observations(self) -> float:
        """Count of this user's own logged outcomes folded into this posterior (alpha + beta
        minus the population prior's own two pseudo-observations)."""
        return (self.alpha - POPULATION_PRIOR_ALPHA) + (self.beta - POPULATION_PRIOR_BETA)


def population_prior() -> dict[str, ArmPosterior]:
    """The cold-start posterior: uniform Beta(1, 1) for all 48 arms.

    This is what a brand-new user (zero rows in `nudges`) is sampled from — spec §9.3's "population
    prior" before any per-user history exists.
    """
    return {
        arm.arm_id: ArmPosterior(arm.arm_id, POPULATION_PRIOR_ALPHA, POPULATION_PRIOR_BETA)
        for arm in ALL_ARMS
    }


def update_posterior(
    prior: Mapping[str, ArmPosterior], history: Iterable[ArmOutcome]
) -> dict[str, ArmPosterior]:
    """Fold this user's (arm, reward) history onto `prior`, one conjugate Beta-Bernoulli update per
    outcome: a reward increments that arm's alpha by 1, a miss increments its beta by 1. Order does
    not matter — Beta-Bernoulli updates commute.

    `prior` is not mutated; a new dict is returned. Raises `ValueError` for any `arm_id` that isn't
    one of the 48 canonical arms (app/main.py turns this into an HTTP 422 — malformed history from
    a caller should fail loudly, not silently get dropped or credited to the wrong arm).
    """
    posterior = dict(prior)
    for outcome in history:
        if outcome.arm_id not in ARMS_BY_ID:
            raise ValueError(
                f"Unknown arm_id {outcome.arm_id!r}; must be one of the 48 canonical arms "
                "(see app/nudge_bandit.ALL_ARMS)."
            )
        current = posterior.get(outcome.arm_id) or ArmPosterior(
            outcome.arm_id, POPULATION_PRIOR_ALPHA, POPULATION_PRIOR_BETA
        )
        if outcome.rewarded:
            posterior[outcome.arm_id] = ArmPosterior(outcome.arm_id, current.alpha + 1.0, current.beta)
        else:
            posterior[outcome.arm_id] = ArmPosterior(outcome.arm_id, current.alpha, current.beta + 1.0)
    return posterior


def eligible_arms(
    *,
    tone: Optional[CoachVoice] = None,
    timing_slot: Optional[NudgeTimingSlot] = None,
    format: Optional[NudgeFormat] = None,
) -> tuple[Arm, ...]:
    """Narrow the 48-arm space to those matching whichever context constraints the caller already
    knows, leaving the rest free for the bandit to choose.

    app/main.py uses this so a fixed product setting (the user's chosen coach voice, spec §5.13)
    or an already-known timing slot (derived from the current hour) constrains the bandit rather
    than being fought by it, while any dimension left `None` stays fully bandit-controlled. Since
    every one of the 48 arms is a member of the full cross product of `TONES` x `TIMING_SLOTS` x
    `FORMATS`, any combination of real enum values always matches at least one arm.
    """
    return tuple(
        arm
        for arm in ALL_ARMS
        if (tone is None or arm.tone == tone)
        and (timing_slot is None or arm.timing_slot == timing_slot)
        and (format is None or arm.format == format)
    )


def select_arm(
    posterior: Mapping[str, ArmPosterior],
    *,
    candidates: Sequence[Arm] = ALL_ARMS,
    rng: Optional[random.Random] = None,
) -> Arm:
    """Thompson sampling: draw one sample from each candidate arm's Beta(alpha, beta) posterior and
    return the arm with the highest sample.

    This is the actual exploration/exploitation mechanism — an arm with a high posterior mean is
    *likely* to produce a high sample (exploit), but a rarely-tried arm has a wide posterior and can
    still win on a lucky draw (explore), all without an explicit epsilon or UCB bonus term.

    `rng` defaults to a fresh, unseeded `random.Random()` (genuine randomness) but accepts a seeded
    one for reproducible tests/debugging. Raises `ValueError` if `candidates` is empty.
    """
    if not candidates:
        raise ValueError("select_arm: candidates must be non-empty")
    rng = rng if rng is not None else random.Random()
    best_arm = candidates[0]
    best_sample = -1.0
    for arm in candidates:
        arm_posterior = posterior.get(arm.arm_id) or ArmPosterior(
            arm.arm_id, POPULATION_PRIOR_ALPHA, POPULATION_PRIOR_BETA
        )
        sample = rng.betavariate(arm_posterior.alpha, arm_posterior.beta)
        if sample > best_sample:
            best_sample = sample
            best_arm = arm
    return best_arm


def thompson_sample_arm(
    history: Iterable[ArmOutcome] = (),
    *,
    tone: Optional[CoachVoice] = None,
    timing_slot: Optional[NudgeTimingSlot] = None,
    format: Optional[NudgeFormat] = None,
    rng: Optional[random.Random] = None,
    seed: Optional[int] = None,
) -> tuple[Arm, dict[str, ArmPosterior]]:
    """The end-to-end entry point app/main.py's `/nudge` endpoint calls: population prior + this
    user's history -> per-user posterior -> context-narrowed Thompson sample.

    Returns `(chosen_arm, full_posterior)` — the caller uses `full_posterior[chosen_arm.arm_id]` to
    report the sampled arm's posterior mean alongside the pick (useful for logging/debugging, same
    spirit as `/risk` returning `p_miss` instead of just a tier).

    `seed` is a convenience for deterministic callers/tests: `random.Random(seed)` when given,
    otherwise `rng` (for callers that already hold a `random.Random`), otherwise a fresh unseeded
    RNG. Passing both `rng` and `seed` is redundant; `seed` wins.
    """
    if seed is not None:
        rng = random.Random(seed)
    elif rng is None:
        rng = random.Random()

    prior = population_prior()
    posterior = update_posterior(prior, history)
    candidates = eligible_arms(tone=tone, timing_slot=timing_slot, format=format)
    if not candidates:
        # Defensive only: every enum-valued combination of tone/timing_slot/format is a member of
        # the full cross product that defines ALL_ARMS, so this is unreachable today. Kept as a
        # safety net (rather than a silent empty pick) in case the arm space is ever narrowed
        # in a future change.
        candidates = ALL_ARMS
    arm = select_arm(posterior, candidates=candidates, rng=rng)
    return arm, posterior
