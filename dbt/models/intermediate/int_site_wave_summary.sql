-- int_site_wave_summary.sql
-- Intermediate model summarizing wave conditions per site
-- Aggregates historical wave observations from stg_wave into one row per site
--
-- NOTE: Focuses on average wave height (operational/maintenance constraint)
--       and max wave height (structural survivability limit).
-- CHANGE: Added p90, p95 wave heights and maintenance window percentage
--         using approx_quantiles — reflects 19 years of hourly observations.

with wave_stats as (
    select
        site_id,
        location_name                                       as site_name,
        avg(wave_height)                                    as avg_wave_height_m,
        max(wave_height)                                    as max_wave_height_m,
        avg(wave_period)                                    as avg_wave_period_s,
        count(record_id)                                    as wave_sample_count,
        -- Extreme wave statistics for structural engineering
        approx_quantiles(wave_height, 100)[offset(90)]     as p90_wave_height_m,
        approx_quantiles(wave_height, 100)[offset(95)]     as p95_wave_height_m,
        -- Maintenance window: % of hours with wave height < 1.5m
        -- 1.5m is the standard threshold for crew transfer vessel operability
        countif(wave_height < 1.5) / count(*)              as maintenance_window_pct
    from {{ ref('stg_wave') }}
    group by 1, 2
)

select
    site_id,
    site_name,
    round(avg_wave_height_m,        2) as avg_wave_height_m,
    round(max_wave_height_m,        2) as max_wave_height_m,
    round(avg_wave_period_s,        2) as avg_wave_period_s,
    wave_sample_count,
    round(p90_wave_height_m,        2) as p90_wave_height_m,
    round(p95_wave_height_m,        2) as p95_wave_height_m,
    round(maintenance_window_pct,   4) as maintenance_window_pct

from wave_stats