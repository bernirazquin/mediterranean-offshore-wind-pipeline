-- int_site_wave_score.sql
-- Owns all wave scoring logic for each Gulf of Lion site.
-- Consumes int_site_wave_summary (aggregated wave statistics).
-- Produces one row per site with a normalised 0–1 wave score.
--
-- Scoring rules:
--   wave_score: penalizes sites with high average waves (maintenance constraint).
--               0m = 1.0 score, linearly decreasing to 0.0 at 3m+ avg height.
--   survivability_class: evaluates extreme conditions for structural engineering limits.
--
-- This model is the single source of truth for wave scoring.

with base as (
    select
        site_id,
        site_name,
        avg_wave_height_m,
        max_wave_height_m,
        avg_wave_period_s
    from {{ ref('int_site_wave_summary') }}
),

scored as (
    select
        *,
        -- Normalised wave score: 1.0 for flat water, linearly dropping to 0.0 at 3m+
        round(greatest(1.0 - (avg_wave_height_m / 3.0), 0.0), 4) as wave_score,

        -- Survivability flag: assesses max historical wave heights
        case
            when max_wave_height_m < 8  then 'high'
            when max_wave_height_m < 12 then 'medium'
            else                             'low'
        end as survivability_class,

        -- Sea State classification based on wave period
        -- < 6s means steep, choppy waves (hard for maintenance vessels)
        -- > 10s means long, rolling swells
        case
            when avg_wave_period_s < 6 then 'choppy'
            when avg_wave_period_s <= 10 then 'moderate'
            else                              'swell'
        end as sea_state_class

    from base
)

select
    site_id,
    site_name,
    avg_wave_height_m,
    max_wave_height_m,
    avg_wave_period_s,
    wave_score,
    survivability_class,
    sea_state_class

from scored