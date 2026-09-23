"""Tests for app/nudge_bandit.py — the Thompson-sampling nudge bandit (docs/spec.md §9.3).

Unit-tests the bandit module directly (no FastAPI/HTTP involved — see tests/test_main.py's /nudge
section for the endpoint-level tests). Statistical assertions here use fixed seeds and posteriors
separated widely enough that failure probability is astronomically small, not flaky "run it enough
times and hope" tests.
"""

from __future__ import annotations

import random

import pytest

from app.models import CoachVoice, NudgeFormat, NudgeTimingSlot
from app.nudge_bandit import (
    ALL_ARMS,
    ARMS_BY_ID,
    FORMATS,
    POPULATION_PRIOR_ALPHA,
    POPULATION_PRIOR_BETA,
    TIMING_SLOTS,
    TONES,
    Arm,
    ArmOutcome,
    ArmPosterior,
    eligible_arms,
    population_prior,
    select_arm,
    thompson_sample_arm,
    update_posterior,
)


# ---------------------------------------------------------------------------
# Arm space — spec.md §9.3: "tone (4) x timing slot (4) x format (3) = 48 arms".
# ---------------------------------------------------------------------------


def test_arm_space_has_exactly_48_arms() -> None:
    assert len(TONES) == 4
    assert len(TIMING_SLOTS) == 4
    assert len(FORMATS) == 3
    assert len(ALL_ARMS) == 48


def test_all_arm_ids_are_unique() -> None:
    ids = [arm.arm_id for arm in ALL_ARMS]
    assert len(ids) == len(set(ids)) == 48


def test_arms_by_id_round_trips_every_arm() -> None:
    for arm in ALL_ARMS:
        assert ARMS_BY_ID[arm.arm_id] is arm


def test_arm_id_format_matches_tone_slot_format() -> None:
    arm = Arm(tone=CoachVoice.HYPE, timing_slot=NudgeTimingSlot.MORNING, format=NudgeFormat.PUSH)
    assert arm.arm_id == "hype:morning:push"


def test_every_tone_slot_format_combination_is_covered() -> None:
    """ALL_ARMS must be exactly the full cross product of TONES x TIMING_SLOTS x FORMATS — no
    combination missing, none extra."""
    seen = {(arm.tone, arm.timing_slot, arm.format) for arm in ALL_ARMS}
    expected = {(tone, slot, fmt) for tone in TONES for slot in TIMING_SLOTS for fmt in FORMATS}
    assert seen == expected


# ---------------------------------------------------------------------------
# Population prior — spec.md §9.3 cold start.
# ---------------------------------------------------------------------------


def test_population_prior_covers_all_48_arms_uniformly() -> None:
    prior = population_prior()
    assert len(prior) == 48
    for arm in ALL_ARMS:
        posterior = prior[arm.arm_id]
        assert posterior.alpha == POPULATION_PRIOR_ALPHA == 1.0
        assert posterior.beta == POPULATION_PRIOR_BETA == 1.0
        assert posterior.mean == pytest.approx(0.5)


def test_population_prior_alpha_beta_are_one_uniform_distribution() -> None:
    """Beta(1, 1) is exactly the uniform distribution on [0, 1] — the 'no information yet' prior."""
    posterior = population_prior()[ALL_ARMS[0].arm_id]
    assert posterior.alpha == 1.0
    assert posterior.beta == 1.0


# ---------------------------------------------------------------------------
# Posterior update — per-user (arm, reward) folding (spec.md §9.3).
# ---------------------------------------------------------------------------


def test_update_posterior_increments_alpha_on_reward() -> None:
    prior = population_prior()
    arm_id = ALL_ARMS[0].arm_id
    posterior = update_posterior(prior, [ArmOutcome(arm_id=arm_id, rewarded=True)])
    assert posterior[arm_id].alpha == 2.0
    assert posterior[arm_id].beta == 1.0
    # Every other arm is untouched.
    for arm in ALL_ARMS[1:]:
        assert posterior[arm.arm_id] == prior[arm.arm_id]


def test_update_posterior_increments_beta_on_miss() -> None:
    prior = population_prior()
    arm_id = ALL_ARMS[0].arm_id
    posterior = update_posterior(prior, [ArmOutcome(arm_id=arm_id, rewarded=False)])
    assert posterior[arm_id].alpha == 1.0
    assert posterior[arm_id].beta == 2.0


def test_update_posterior_folds_many_outcomes_for_the_same_arm() -> None:
    prior = population_prior()
    arm_id = ALL_ARMS[0].arm_id
    history = [ArmOutcome(arm_id=arm_id, rewarded=True)] * 7 + [ArmOutcome(arm_id=arm_id, rewarded=False)] * 3
    posterior = update_posterior(prior, history)
    assert posterior[arm_id].alpha == 1.0 + 7
    assert posterior[arm_id].beta == 1.0 + 3
    assert posterior[arm_id].mean == pytest.approx(8 / 12)


def test_update_posterior_does_not_mutate_the_input_prior() -> None:
    prior = population_prior()
    arm_id = ALL_ARMS[0].arm_id
    snapshot = prior[arm_id]
    update_posterior(prior, [ArmOutcome(arm_id=arm_id, rewarded=True)])
    assert prior[arm_id] == snapshot


def test_update_posterior_rejects_unknown_arm_id() -> None:
    prior = population_prior()
    with pytest.raises(ValueError, match="Unknown arm_id"):
        update_posterior(prior, [ArmOutcome(arm_id="not_a_real_arm", rewarded=True)])


def test_update_posterior_with_empty_history_returns_prior_unchanged_values() -> None:
    prior = population_prior()
    posterior = update_posterior(prior, [])
    for arm in ALL_ARMS:
        assert posterior[arm.arm_id] == prior[arm.arm_id]


# ---------------------------------------------------------------------------
# eligible_arms — context narrowing.
# ---------------------------------------------------------------------------


def test_eligible_arms_with_no_constraints_returns_all_48() -> None:
    assert eligible_arms() == ALL_ARMS


def test_eligible_arms_narrows_by_timing_slot() -> None:
    candidates = eligible_arms(timing_slot=NudgeTimingSlot.MORNING)
    assert len(candidates) == 4 * 3  # 4 tones x 3 formats
    assert all(arm.timing_slot == NudgeTimingSlot.MORNING for arm in candidates)


def test_eligible_arms_narrows_by_tone() -> None:
    candidates = eligible_arms(tone=CoachVoice.CHILL)
    assert len(candidates) == 4 * 3  # 4 slots x 3 formats
    assert all(arm.tone == CoachVoice.CHILL for arm in candidates)


def test_eligible_arms_narrows_by_format() -> None:
    candidates = eligible_arms(format=NudgeFormat.SHIELD_COPY)
    assert len(candidates) == 4 * 4  # 4 tones x 4 slots
    assert all(arm.format == NudgeFormat.SHIELD_COPY for arm in candidates)


def test_eligible_arms_with_all_three_constraints_returns_exactly_one_arm() -> None:
    candidates = eligible_arms(
        tone=CoachVoice.DATA, timing_slot=NudgeTimingSlot.EVENING, format=NudgeFormat.WIDGET_COPY
    )
    assert candidates == (Arm(CoachVoice.DATA, NudgeTimingSlot.EVENING, NudgeFormat.WIDGET_COPY),)


# ---------------------------------------------------------------------------
# select_arm — the actual Thompson-sampling draw.
# ---------------------------------------------------------------------------


def test_select_arm_rejects_empty_candidates() -> None:
    with pytest.raises(ValueError, match="non-empty"):
        select_arm(population_prior(), candidates=())


def test_select_arm_picks_the_only_candidate() -> None:
    prior = population_prior()
    arm = ALL_ARMS[5]
    chosen = select_arm(prior, candidates=(arm,), rng=random.Random(0))
    assert chosen == arm


def test_select_arm_overwhelmingly_favors_a_much_higher_posterior_mean() -> None:
    """A near-certain-good arm (alpha=1000, beta=1) vs. a near-certain-bad one (alpha=1, beta=1000)
    should win essentially every draw — the separation is wide enough that this is deterministic in
    practice, not a statistical coin flip, so a fixed seed is enough for a non-flaky assertion."""
    prior = population_prior()
    good_id, bad_id = ALL_ARMS[0].arm_id, ALL_ARMS[1].arm_id
    prior = dict(prior)
    prior[good_id] = ArmPosterior(good_id, alpha=1000.0, beta=1.0)
    prior[bad_id] = ArmPosterior(bad_id, alpha=1.0, beta=1000.0)
    candidates = (ALL_ARMS[0], ALL_ARMS[1])

    rng = random.Random(42)
    wins = sum(1 for _ in range(50) if select_arm(prior, candidates=candidates, rng=rng) == ALL_ARMS[0])
    assert wins == 50


def test_select_arm_is_deterministic_for_a_seeded_rng() -> None:
    prior = population_prior()
    first = select_arm(prior, candidates=ALL_ARMS, rng=random.Random(7))
    second = select_arm(prior, candidates=ALL_ARMS, rng=random.Random(7))
    assert first == second


def test_select_arm_falls_back_to_population_prior_for_an_arm_missing_from_posterior() -> None:
    """Defensive path: if a caller hands select_arm a posterior dict missing an arm entirely (not
    possible via update_posterior/population_prior, but select_arm's contract doesn't require a
    complete dict), it should treat that arm as the population prior rather than KeyError."""
    sparse_posterior: dict[str, ArmPosterior] = {}
    arm = ALL_ARMS[0]
    chosen = select_arm(sparse_posterior, candidates=(arm,), rng=random.Random(1))
    assert chosen == arm


# ---------------------------------------------------------------------------
# thompson_sample_arm — the end-to-end entry point app/main.py calls.
# ---------------------------------------------------------------------------


def test_thompson_sample_arm_cold_start_returns_a_valid_arm_and_uniform_posterior() -> None:
    arm, posterior = thompson_sample_arm(seed=1)
    assert arm in ALL_ARMS
    assert len(posterior) == 48
    assert posterior[arm.arm_id].mean == pytest.approx(0.5)  # pure population prior, no history


def test_thompson_sample_arm_is_deterministic_for_the_same_seed() -> None:
    first, _ = thompson_sample_arm(seed=123)
    second, _ = thompson_sample_arm(seed=123)
    assert first == second


def test_thompson_sample_arm_respects_timing_slot_context() -> None:
    arm, _ = thompson_sample_arm(timing_slot=NudgeTimingSlot.PRE_GYM, seed=9)
    assert arm.timing_slot == NudgeTimingSlot.PRE_GYM


def test_thompson_sample_arm_respects_tone_context() -> None:
    arm, _ = thompson_sample_arm(tone=CoachVoice.TOUGH_LOVE, seed=9)
    assert arm.tone == CoachVoice.TOUGH_LOVE


def test_thompson_sample_arm_respects_format_context() -> None:
    arm, _ = thompson_sample_arm(format=NudgeFormat.SHIELD_COPY, seed=9)
    assert arm.format == NudgeFormat.SHIELD_COPY


def test_thompson_sample_arm_with_all_context_constraints_returns_that_exact_arm() -> None:
    arm, _ = thompson_sample_arm(
        tone=CoachVoice.HYPE,
        timing_slot=NudgeTimingSlot.MORNING,
        format=NudgeFormat.PUSH,
        seed=9,
    )
    assert arm == Arm(CoachVoice.HYPE, NudgeTimingSlot.MORNING, NudgeFormat.PUSH)


def test_thompson_sample_arm_learns_toward_a_strong_per_user_winner() -> None:
    """After enough logged wins for one arm (and losses for every rival *within the same narrowed
    context*), the bandit should pick the winning arm on a fresh sample far more often than chance —
    the per-user 'bandit with population prior' behavior spec.md §9.3 asks for.

    Narrows to `timing_slot=MORNING` (12 arms) so the comparison is winner-vs-trained-rivals, not
    winner-vs-the-other-36-arms'-wide-open-population-prior — with 36 untouched Beta(1,1) arms in
    the mix, one of them drawing a sample near 1 by chance is *expected* exploration behavior, not
    something a single-arm 'winner' test should be measuring against.
    """
    morning_arms = eligible_arms(timing_slot=NudgeTimingSlot.MORNING)
    assert len(morning_arms) == 12
    winner, *rivals = morning_arms

    history = [ArmOutcome(arm_id=winner.arm_id, rewarded=True) for _ in range(20)]
    for rival in rivals:
        history += [ArmOutcome(arm_id=rival.arm_id, rewarded=False) for _ in range(20)]

    trials = 30
    wins = sum(
        1
        for trial_seed in range(trials)
        if thompson_sample_arm(history, timing_slot=NudgeTimingSlot.MORNING, seed=2000 + trial_seed)[0]
        == winner
    )

    assert wins >= trials * 0.9  # heavily and consistently biased toward the trained winner


def test_thompson_sample_arm_rejects_unknown_arm_id_in_history() -> None:
    with pytest.raises(ValueError, match="Unknown arm_id"):
        thompson_sample_arm([ArmOutcome(arm_id="nonsense", rewarded=True)], seed=1)


def test_thompson_sample_arm_history_does_not_affect_other_users_call_without_that_history() -> None:
    """Statelessness: two independent calls with different history inputs don't leak into each
    other — each call rebuilds its posterior from population_prior() + its own `history` arg only."""
    winner = ALL_ARMS[20]
    history = [ArmOutcome(arm_id=winner.arm_id, rewarded=True) for _ in range(20)]

    _, posterior_with_history = thompson_sample_arm(history, seed=5)
    _, posterior_without_history = thompson_sample_arm([], seed=5)

    assert posterior_with_history[winner.arm_id].alpha == 21.0
    assert posterior_without_history[winner.arm_id].alpha == 1.0
