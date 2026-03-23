-- int_site_spatial_summary.sql
-- Summarizes the static spatial characteristics of each Gulf of Lion grid point.

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
    raster_cells_sampled,

    case
        when depth_m <= 50  then 'fixed'
        when depth_m <= 200 then 'floating'
        else                     'not_viable'
    end as turbine_type,

    round(1 - least(depth_m, 200) / 200, 4) as depth_score,
    round(1 - least(distance_to_coast_km, 200) / 200, 4) as coast_score

from {{ ref('int_site_spatial_samples') }}