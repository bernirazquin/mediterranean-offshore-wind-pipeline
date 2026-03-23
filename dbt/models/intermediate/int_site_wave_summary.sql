-- int_site_wave_summary.sql
-- Intermediate model summarizing wave conditions per site
-- Aggregates historical wave observations from stg_wave into one row per site
--
-- NOTE: Focuses on average wave height (operational/maintenance constraint) 
--       and max wave height (structural survivability limit).

with wave_stats as (
    select
        site_id,
        location_name as site_name,
        avg(wave_height) as avg_wave_height_m,
        max(wave_height) as max_wave_height_m,
        avg(wave_period)  as avg_wave_period_s,
        count(record_id)  as wave_sample_count
    from {{ ref('stg_wave') }}
    group by 1, 2
)

select
    site_id,
    site_name,
    round(avg_wave_height_m, 2) as avg_wave_height_m,
    round(max_wave_height_m, 2) as max_wave_height_m,
    round(avg_wave_period_s, 2) as avg_wave_period_s,
    wave_sample_count

from wave_stats