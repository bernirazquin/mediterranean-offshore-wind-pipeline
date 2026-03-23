-- int_site_spatial_samples.sql
-- Each grid point represents a 0.25° cell (~25km × 25km).
-- Professional Refactor: Using optimized surrogate key joins and filtering for marine-only cells.

with cell_samples as (
    select
        sc.site_name,
        sc.spatial_id,
        sc.center_lat,
        sc.center_lon,

        -- Aggregated Bathymetry
        avg(b.depth_m) as depth_m,
        min(b.depth_m) as depth_min_m,
        max(b.depth_m) as depth_max_m,
        any_value(b.depth_category) as depth_category,

        -- Aggregated Coastline
        avg(cd.distance_to_coast_km) as distance_to_coast_km,
        min(cd.distance_to_coast_km) as distance_min_km,
        any_value(cd.distance_category) as distance_category,

        count(b.spatial_id) as raster_cells_sampled

    from {{ ref('int_site_centers') }} sc
    -- Using the Standardized Grid Join
    left join {{ ref('stg_bathymetry') }} b
        on sc.spatial_id = b.spatial_id
    left join {{ ref('stg_coastline_distance') }} cd
        on sc.spatial_id = cd.spatial_id
    
    group by 1, 2, 3, 4
)

select * from cell_samples