-- int_site_spatial_samples.sql
-- Aggregates high-resolution raster data for each 0.25° grid cell
-- Each grid point represents a cell ~25km × 25km
--
-- FIX: raster_cells_sampled renamed to sample_count per nomenclature standard.
--      This name is reusable across wind/wave density counts in future models.
-- NOTE: Left joins are intentional — a site with no bathymetry/coastline match
--       will surface as null here rather than silently disappear, making data
--       gaps visible for debugging. int_site_spatial_summary filters them out.

with cell_samples as (
    select
        sc.site_name,
        sc.site_id,
        sc.spatial_id,
        sc.center_lat,
        sc.center_lon,

        -- purified bathymetry
        -- Only average points that are actually in the water (< 0)
        avg(case when b.elevation_m < 0 then abs(b.elevation_m) end) as depth_m,
        min(case when b.elevation_m < 0 then abs(b.elevation_m) end) as depth_min_m,
        max(case when b.elevation_m < 0 then abs(b.elevation_m) end) as depth_max_m,

        -- marine coverage math
        -- (Count of points < 0) / (Total points in the 25km cell)
        countif(b.elevation_m < 0) / count(b.spatial_id) as marine_coverage_pct,

        -- Aggregated Coastline Distance
        avg(cd.distance_to_coast_km)    as distance_to_coast_km,
        min(cd.distance_to_coast_km)    as distance_min_km,

        -- Re-derived from cell average — not grabbed arbitrarily
        -- from a single pixel via any_value().
        -- Thresholds match the hard gates in int_site_composite_score:
        --   nearshore < 11km (fixed turbine minimum gate)
        --   midshore  <= 50km
        --   offshore  > 50km
        case
            when avg(cd.distance_to_coast_km) < 11  then 'nearshore'
            when avg(cd.distance_to_coast_km) <= 50 then 'midshore'
            else                                         'offshore'
        end as distance_category,

        -- Renamed from raster_cells_sampled
        count(b.spatial_id) as sample_count

    from {{ ref('int_site_centers') }} sc
    left join {{ ref('stg_bathymetry') }}         b  on sc.spatial_id = b.spatial_id
    left join {{ ref('stg_coastline_distance') }}  cd on sc.spatial_id = cd.spatial_id

    group by 1, 2, 3, 4, 5
)

select 
    *,
    -- Apply site-level category based on the purified average
    case
        when depth_m < 50  then 'shallow'
        when depth_m < 200 then 'transitional'
        else 'deep'
    end as depth_category

from cell_samples
