-- int_site_composite_score.sql
-- Joins spatial, wind, and wave scores into a single composite score per site.
-- This is the deepest layer of business logic — the mart reads from here only.
--
-- Minimum threshold gates (physical inputs):
--   depth_m              >= 10m  — eliminates truly shallow/inland sites
--   distance_to_coast_km >= 11km — eliminates near-shore sites (fixed turbines)
--   distance_to_coast_km >= 5km  — minimum for floating turbines
--   depth_m              <= 1000m — upper limit aligned with floating turbine range
--
-- Survivability penalty applied to final_score:
--   high survivability   → 1.0× (no penalty)
--   medium survivability → 0.9× (mild penalty)
--   low survivability    → 0.7× (meaningful penalty, site still visible)
--
-- CHANGE: Weights updated from 30/50/20 to 40/40/20
-- CHANGE: Survivability multiplier added to final_score
-- CHANGE: nearshore_penalty removed — dropped from spatial score model
-- CHANGE: Distance gate is now turbine-type aware (fixed >= 11km, floating >= 5km)
-- NOTE:   Manual exclusions (visual land-centroid misplacements) are applied
--         in mart_offshore_site_prioritization, not here. This model scores
--         all physically viable sites without override logic.

with spatial as (
    select * from {{ ref('int_site_spatial_score') }}
    where turbine_type != 'not_viable'
),

wind as (
    select * from {{ ref('int_site_wind_score') }}
),

wave as (
    select * from {{ ref('int_site_wave_score') }}
),

joined as (
    select
        sp.site_name,
        sp.site_id,
        sp.spatial_id,
        sp.center_lat,
        sp.center_lon,
        sp.depth_m,
        sp.turbine_type,
        sp.distance_to_coast_km,
        sp.spatial_score,
        w.avg_wind_speed_ms,
        w.wind_power_potential_index,
        w.wind_potential_class,
        w.wind_score,
        wv.avg_wave_height_m,
        wv.max_wave_height_m,
        wv.avg_wave_period_s,
        wv.sea_state_class,
        wv.survivability_class,
        wv.wave_score,
        case
            when wv.survivability_class = 'high'   then 1.0
            when wv.survivability_class = 'medium' then 0.9
            else                                        0.7
        end as survivability_multiplier,
        round(
            (0.40 * sp.spatial_score)
            + (0.40 * w.wind_score)
            + (0.20 * wv.wave_score),
        4) as raw_final_score

    from spatial sp
    inner join wind w  on sp.site_id = w.site_id
    inner join wave wv on sp.site_id = wv.site_id
)

select
    site_name,
    site_id,
    spatial_id,
    center_lat,
    center_lon,
    depth_m,
    turbine_type,
    distance_to_coast_km,
    spatial_score,
    avg_wind_speed_ms,
    wind_power_potential_index,
    wind_potential_class,
    wind_score,
    avg_wave_height_m,
    max_wave_height_m,
    avg_wave_period_s,
    sea_state_class,
    survivability_class,
    wave_score,
    survivability_multiplier,
    raw_final_score,
    round(raw_final_score * survivability_multiplier, 4) as final_score

from joined
where depth_m >= 10
  and depth_m <= 1000
  and (
      (turbine_type = 'fixed'    and distance_to_coast_km >= 11)
   or (turbine_type = 'floating' and distance_to_coast_km >= 5)
  )