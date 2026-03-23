-- int_site_wind_score.sql
-- Owns all wind scoring logic for each Gulf of Lion site.
-- Consumes int_site_wind_summary (aggregated wind statistics).
-- Produces one row per site with a normalised 0–1 wind score.
--
-- Scoring rules:
--   wind_score: linear normalisation against a 12 m/s ideal, capped at 1.0.
--   12 m/s is the IEC Class I reference mean wind speed for offshore turbines.
--   Sites below 6 m/s average are flagged as low_potential.
--
-- This model is the single source of truth for wind scoring.
-- If the reference speed or viability floor needs to change, change it here only.

with base as (
    select
        site_id,
        site_name,
        avg_wind_speed_ms,
        wind_stddev,
        max_gust_ms,
        wind_power_potential_index
    from {{ ref('int_site_wind_summary') }}
),

scored as (
    select
        *,
        -- Normalised wind score: 12 m/s average = 1.0, linear below
        round(least(avg_wind_speed_ms / 12, 1), 4) as wind_score,

        -- Viability flag: sites below 6 m/s are unlikely to be commercially viable
        case
            when avg_wind_speed_ms >= 9  then 'high'
            when avg_wind_speed_ms >= 6  then 'medium'
            else                              'low'
        end as wind_potential_class

    from base
)

select
    site_id,
    site_name,
    avg_wind_speed_ms,
    wind_stddev,
    max_gust_ms,
    wind_power_potential_index,
    wind_score,
    wind_potential_class

from scored