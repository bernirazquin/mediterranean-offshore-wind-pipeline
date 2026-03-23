-- -- int_site_centers.sql
-- Derives the 111 Gulf of Lion grid point centers directly from the site keys
-- in the wind data. No coordinates are hardcoded — lat/lon are parsed from the
-- site key itself (e.g. GULF_OF_LION_41.5_3.25 → lat 41.5, lon 3.25).
--
-- Replaces the old int_site_centers which hardcoded 14 Mediterranean site
-- coordinates in a CASE WHEN block. In the new design, coordinates are
-- encoded in the KV store key and flow through to raw_wind_data automatically.
--
-- Dependencies: stg_wind
-- Used by:      int_site_spatial_samples

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
        -- Safely grab coordinates only if the name has enough parts
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
)

select
    site_name,
    raw_lat as center_lat,
    raw_lon as center_lon,
    
    -- Replace the hardcoded math with the macro!
    {{ generate_grid_id('raw_lat', 'raw_lon') }} as spatial_id

from parsed_coords
where raw_lat is not null