-- int_site_spatial_summary.sql
-- One row per Gulf of Lion grid point summarising static spatial characteristics
-- Upstream: int_site_spatial_samples
--
-- FIX: raster_cells_sampled → sample_count to match int_site_spatial_samples rename.

select
    site_name,
    spatial_id,
    center_lat,
    center_lon,
    depth_m,
    depth_min_m,
    depth_max_m,
    depth_category,
    distance_to_coast_km,
    distance_min_km,
    distance_category,
    sample_count,

    -- Turbine technology viability based on water depth
    case
        when depth_m <= 50  then 'fixed'
        when depth_m <= 200 then 'floating'
        else                     'not_viable'
    end as turbine_type,

    -- Depth score: shallow = 1.0, 200m+ = 0.0
    round(1 - least(depth_m, 200) / 200, 4)              as depth_score,

    -- Coast score: nearshore = 1.0, 200km+ = 0.0
    round(1 - least(distance_to_coast_km, 200) / 200, 4) as coast_score

from {{ ref('int_site_spatial_samples') }}
where depth_m is not null  -- Drop sites with no matched raster data