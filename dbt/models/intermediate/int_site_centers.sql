-- -- int_site_centers.sql
-- Derives the 111 Gulf of Lion grid point centers directly from the site keys
-- in the wind data. No coordinates are hardcoded — lat/lon are parsed from the
-- site key itself (e.g. GULF_OF_LION_41.5_3.25 → lat 41.5, lon 3.25).
--
-- Replaces the old int_site_centers which hardcoded 14 Mediterranean site
-- coordinates in a CASE WHEN block. In the new design, coordinates are
-- encoded in the KV store key and flow through to raw_wind_data automatically.
--
-- Dependencies: stg_wind, stg_bathymetry
-- Used by:      int_site_spatial_samples
--
-- CHANGE: Added bathymetry filter to exclude land cells.
--         9 grid points had zero marine bathymetry samples (confirmed land).
--         Official marine site count is 102, not 111.

with site_extraction as (
    select
        location_name as site_name,
        split(location_name, '_') as name_parts
    from {{ ref('stg_wind') }}
    group by 1, 2
),

parsed_coords as (
    select
        site_name,
        case 
            when array_length(name_parts) >= 5 
            then cast(name_parts[offset(3)] as float64) 
            else null 
        end as raw_lat,
        case 
            when array_length(name_parts) >= 5 
            then cast(name_parts[offset(4)] as float64) 
            else null 
        end as raw_lon
    from site_extraction
),

marine_only as (
    select
        pc.site_name,
        pc.raw_lat,
        pc.raw_lon,
        {{ generate_grid_id('pc.raw_lat', 'pc.raw_lon') }} as spatial_id
    from parsed_coords pc
    -- Ensures only site centroids with at least one confirmed marine bathymetry cell
    -- are retained. Without this, land grid cells with any bathymetry coverage pass
    -- through silently. The is_land = 0 condition enforces the marine-only check;
    -- matching on spatial_id alone is insufficient because stg_bathymetry previously
    -- included land rows that shared a spatial_id with coastal wind grid points.
    inner join {{ ref('stg_bathymetry') }} b
        on {{ generate_grid_id('pc.raw_lat', 'pc.raw_lon') }} = b.spatial_id
        and b.is_land = 0
    where pc.raw_lat is not null
    group by 1, 2, 3, 4
)

select
    site_name,
    raw_lat as center_lat,
    raw_lon as center_lon,
    spatial_id

from marine_only