"""Tests for app/features.py (docs/spec.md §9.2 feature vector construction).

Exercises `vectorize_row`/`to_frame`/`coldstart_features` against hand-built rows shaped like
`public.user_day_features` (backend/supabase/migrations/0004_ml_feature_job.sql) and onboarding
answers, respectively — no DB connection, pure functions of dicts.
"""

from __future__ import annotations

import pandas as pd

from app.features import (
    ALL_FEATURE_COLUMNS,
    BOOLEAN_FEATURE_COLUMNS,
    CATEGORICAL_FEATURE_COLUMNS,
    LABEL_COLUMN,
    NUMERIC_FEATURE_COLUMNS,
    coldstart_features,
    coldstart_frame,
    to_frame,
    vectorize_row,
)

FULL_ROW: dict[str, object] = {
    "day_of_week": 2,
    "hour_of_first_event": 8,
    "streak_length": 5,
    "days_since_last_miss": 3,
    "events_count": 4,
    "verified_events_count": 3,
    "active_goal_count": 2,
    "avg_difficulty_step": 0.5,
    "sleep_hours": None,
    "calendar_density": None,
    "yesterday_completed": True,
    "any_plan_b_offered": False,
    "travel_flag": None,
    "onboarding_fall_off_pattern": None,
    "weather": None,
    LABEL_COLUMN: False,
}


def test_vectorize_row_converts_numeric_columns_to_float() -> None:
    out = vectorize_row(FULL_ROW)
    assert out["day_of_week"] == 2.0
    assert isinstance(out["day_of_week"], float)
    assert out["streak_length"] == 5.0
    assert out["avg_difficulty_step"] == 0.5


def test_vectorize_row_preserves_none_for_missing_numeric() -> None:
    out = vectorize_row(FULL_ROW)
    assert out["sleep_hours"] is None
    assert out["calendar_density"] is None


def test_vectorize_row_converts_booleans_to_zero_one() -> None:
    out = vectorize_row(FULL_ROW)
    assert out["yesterday_completed"] == 1.0
    assert out["any_plan_b_offered"] == 0.0
    assert out["travel_flag"] is None  # None stays None, not coerced to 0.0


def test_vectorize_row_passes_through_missing_key_as_none() -> None:
    out = vectorize_row({})
    for col in NUMERIC_FEATURE_COLUMNS:
        assert out[col] is None
    for col in BOOLEAN_FEATURE_COLUMNS:
        assert out[col] is None
    for col in CATEGORICAL_FEATURE_COLUMNS:
        assert out[col] is None


def test_to_frame_has_every_feature_column() -> None:
    frame = to_frame([FULL_ROW, FULL_ROW])
    assert list(frame.columns) == list(ALL_FEATURE_COLUMNS)
    assert len(frame) == 2


def test_to_frame_marks_categorical_columns_as_category_dtype() -> None:
    frame = to_frame([FULL_ROW])
    for col in CATEGORICAL_FEATURE_COLUMNS:
        assert isinstance(frame[col].dtype, pd.CategoricalDtype)


def test_to_frame_include_label_carries_boolean_label_through() -> None:
    completed_row = dict(FULL_ROW, **{LABEL_COLUMN: False})
    missed_row = dict(FULL_ROW, **{LABEL_COLUMN: True})
    frame = to_frame([completed_row, missed_row], include_label=True)
    assert frame[LABEL_COLUMN].tolist() == [False, True]


def test_to_frame_include_label_handles_unlabeled_rows_as_none() -> None:
    unlabeled_row = dict(FULL_ROW)
    del unlabeled_row[LABEL_COLUMN]
    frame = to_frame([unlabeled_row], include_label=True)
    assert frame[LABEL_COLUMN].iloc[0] is None


def test_to_frame_reads_a_generator_correctly() -> None:
    """Regression guard: to_frame reads `rows` twice internally when include_label=True, so a
    one-shot generator must not silently produce an empty label column."""
    rows = (dict(FULL_ROW) for _ in range(3))
    frame = to_frame(rows, include_label=True)
    assert len(frame) == 3
    assert frame[LABEL_COLUMN].tolist() == [False, False, False]


def test_coldstart_features_computes_workout_gap_ratio() -> None:
    out = coldstart_features(
        {
            "fall_off_pattern": "weekends",
            "daily_phone_hours": 6,
            "current_workouts_per_week": 1,
            "target_workouts_per_week": 4,
        }
    )
    assert out["fall_off_pattern"] == "weekends"
    assert out["daily_phone_hours"] == 6.0
    assert out["workout_gap_ratio"] == 0.75  # (4-1)/4


def test_coldstart_features_clamps_negative_gap_to_zero() -> None:
    """A user already exceeding their stated target shouldn't produce a negative 'gap' feature."""
    out = coldstart_features(
        {"current_workouts_per_week": 5, "target_workouts_per_week": 3}
    )
    assert out["workout_gap_ratio"] == 0.0


def test_coldstart_features_handles_missing_answers() -> None:
    out = coldstart_features({})
    assert out["fall_off_pattern"] is None
    assert out["daily_phone_hours"] is None
    assert out["workout_gap_ratio"] is None


def test_coldstart_frame_shape() -> None:
    rows = [
        {"daily_phone_hours": 5, "current_workouts_per_week": 0, "target_workouts_per_week": 3},
        {"daily_phone_hours": 8, "current_workouts_per_week": 2, "target_workouts_per_week": 2},
    ]
    frame = coldstart_frame(rows)
    assert list(frame.columns) == ["fall_off_pattern", "daily_phone_hours", "workout_gap_ratio"]
    assert len(frame) == 2
