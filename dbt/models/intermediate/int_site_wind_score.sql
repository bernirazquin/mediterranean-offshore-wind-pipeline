-- int_site_wind_score.sql
-- Owns all wind scoring logic for each Gulf of Lion site.
-- Consumes int_site_wind_summary (aggregated wind statistics).
-- Produces one row per site with a normalised 0–1 wind score.
--
-- Scoring rules:
--   wind_score: composite of avg (40%), p50 (40%), and p90 (20%) scores.
--   avg_score: linear normalisation against a 12 m/s ideal (IEC Class I).
--   p50_score: linear normalisation against a 10 m/s ideal (Bankable median).
--   p90_score: linear normalisation against an 18 m/s ideal (Mistral peak).
--   Sites below 6 m/s average are flagged as low_potential.
--
-- This model is the single source of truth for wind scoring.
-- If the reference speeds or weights need to change, change it here only.

with base as (
    select
        site_id,
        site_name,
        avg_wind_speed_ms,
        p50_wind_speed_ms,
        p90_wind_speed_ms,
        wind_stddev,
        max_gust_ms,
        wind_power_potential_index
    from {{ ref('int_site_wind_summary') }}
),

scored as (
    select
        *,
        -- Normalised components
        round(least(avg_wind_speed_ms / 12.0, 1.0), 4) as avg_score,
        round(least(p50_wind_speed_ms / 10.0, 1.0), 4) as p50_score,
        round(least(p90_wind_speed_ms / 18.0, 1.0), 4) as p90_score,

        -- Composite wind score: 40% Avg / 40% P50 / 20% P90
        round(
            (0.40 * least(avg_wind_speed_ms / 12.0, 1.0)) + 
            (0.40 * least(p50_wind_speed_ms / 10.0, 1.0)) + 
            (0.20 * least(p90_wind_speed_ms / 18.0, 1.0)), 
        4) as wind_score,

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
    p50_wind_speed_ms,
    p90_wind_speed_ms,
    wind_stddev,
    max_gust_ms,
    wind_power_potential_index,
    avg_score,
    p50_score,
    p90_score,
    wind_score,
    wind_potential_class

from scored