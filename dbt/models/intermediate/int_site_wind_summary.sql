-- int_site_wind_summary.sql
-- Intermediate model summarizing wind conditions per site
-- Aggregates historical wind observations from stg_wind into one row per site
--
-- FIX: Joins on site_id (surrogate key) instead of raw location_name string,
--      making this model refactor-safe and consistent with the rest of the DAG.
-- FIX: References wind_speed_ms (renamed from wind_speed_100m in stg_wind).
-- CHANGE: Added p50, p90 wind speeds and operational availability percentage
--         using approx_quantiles — reflects 19 years of hourly observations.

with wind_stats as (
    select
        site_id,
        location_name                                       as site_name,
        avg(wind_speed_ms)                                  as avg_wind_speed_ms,
        stddev(wind_speed_ms)                               as wind_stddev,
        max(wind_speed_ms)                                  as max_gust_ms,
        -- Wind power is proportional to the cube of wind speed: P ∝ v³
        avg(pow(wind_speed_ms, 3))                          as wind_power_potential_index,
        -- Percentile wind speeds for energy yield and risk assessment
        approx_quantiles(wind_speed_ms, 100)[offset(50)]   as p50_wind_speed_ms,
        approx_quantiles(wind_speed_ms, 100)[offset(90)]   as p90_wind_speed_ms,
        -- Operational availability: % of hours within turbine operating range
        -- 6 m/s = cut-in speed, 25 m/s = cut-out speed
        countif(wind_speed_ms >= 6.0 and wind_speed_ms <= 25.0)
            / count(*)                                      as operational_availability_pct
    from {{ ref('stg_wind') }}
    group by 1, 2
)

select
    site_id,
    site_name,
    round(avg_wind_speed_ms,            2) as avg_wind_speed_ms,
    round(wind_stddev,                  2) as wind_stddev,
    round(max_gust_ms,                  2) as max_gust_ms,
    round(wind_power_potential_index,   2) as wind_power_potential_index,
    round(p50_wind_speed_ms,            2) as p50_wind_speed_ms,
    round(p90_wind_speed_ms,            2) as p90_wind_speed_ms,
    round(operational_availability_pct, 4) as operational_availability_pct

from wind_stats