-- Each grid point represents a 0.25° cell (~25km × 25km).
-- Instead of a single coordinate snap, we sample all raster cells within
-- the cell footprint (±0.125°) and aggregate the values to get a more representative sample of the site conditions.

with cell_samples as (
    select
        sc.site_name,
        sc.center_lat,
        sc.center_lon,

        AVG(b.depth_m)                  as depth_m,
        MIN(b.depth_m)                  as depth_min_m,
        MAX(b.depth_m)                  as depth_max_m,
        ANY_VALUE(b.depth_category)     as depth_category,
        LOGICAL_OR(b.viable_fixed)      as viable_fixed,
        LOGICAL_OR(b.viable_floating)   as viable_floating,

        AVG(cd.distance_to_coast_km)    as distance_to_coast_km,
        MIN(cd.distance_to_coast_km)    as distance_min_km,
        ANY_VALUE(cd.distance_category) as distance_category,

        COUNT(*)                        as raster_cells_sampled

    from {{ ref('int_site_centers') }} sc
    join {{ ref('stg_bathymetry') }} b
        on b.latitude  between sc.center_lat - 0.125 and sc.center_lat + 0.125
        and b.longitude between sc.center_lon - 0.125 and sc.center_lon + 0.125
    join {{ ref('stg_coastline_distance') }} cd
        on ROUND(b.latitude, 3)  = ROUND(cd.latitude, 3)
        and ROUND(b.longitude, 3) = ROUND(cd.longitude, 3)
    group by sc.site_name, sc.center_lat, sc.center_lon
)

select * from cell_samples
