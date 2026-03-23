-- Summarises the static spatial characteristics of each Gulf of Lion grid point.
-- One row per site — this is the spatial dimension table used by fct_site_suitability
-- and Looker Studio.
--
-- Turbine type is assigned based on average cell depth:
--   fixed      → 0 to 50m   (monopile/jacket foundations)
--   floating   → 50 to 200m (semi-submersible/spar)
--   not_viable → > 200m     (beyond current technology)
--
-- Dependencies: int_site_spatial_samples
-- Used by:      fct_site_suitability

select
    site_name,
    center_lat,
    center_lon,
    depth_m,
    depth_min_m,
    depth_max_m,
    depth_category,
    distance_to_coast_km,
    distance_min_km,
    distance_category,
    raster_cells_sampled,

    -- Turbine type based on average depth
    case
        when depth_m <= 50  then 'fixed'
        when depth_m <= 200 then 'floating'
        else                     'not_viable'
    end as turbine_type,

    -- Depth score: shallower is cheaper to install (0–1 scale)
    -- Capped at 200m since deeper = not viable anyway
    round(
        1 - least(depth_m, 200) / 200,
    4) as depth_score,

    -- Coast score: closer to coast = cheaper grid connection (0–1 scale)
    -- Capped at 200km
    round(
        1 - least(distance_to_coast_km, 200) / 200,
    4) as coast_score

from {{ ref('int_site_spatial_samples') }}