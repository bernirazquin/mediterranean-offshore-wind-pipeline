-- stg_coastline_distance.sql
-- Staging model for coastline distance data
-- Filters out land cells via inner join with bathymetry
-- Source: Natural Earth 1:10m coastline, scipy distance transform, WGS84
-- Casting coordinates to strings before hashing to avoid float precision errors

select
    -- Using a hash of the raw coordinates to ensure 1:1 join with bathymetry
    {{ dbt_utils.generate_surrogate_key(['c.latitude', 'c.longitude']) }} as raw_pixel_id,
    
    c.latitude,
    c.longitude,
    c.distance_to_coast_km,

    -- Map this pixel to 0.25 degree grid
    {{ dbt_utils.generate_surrogate_key([
        'cast(round(floor(c.latitude / 0.25) * 0.25 + 0.125, 4) as string)',
        'cast(round(floor(c.longitude / 0.25) * 0.25 + 0.125, 4) as string)'
    ]) }} as spatial_id,

    case
        when c.distance_to_coast_km < 50  then 'nearshore'
        when c.distance_to_coast_km < 100 then 'midshore'
        else                                   'offshore'
    end as distance_category

from {{ source('med_wind_prod', 'raw_coastline_distance') }} c

-- Inner join to marine pixels only: filters out land-adjacent coastline pixels where
-- the matching bathymetry record has positive elevation (i.e. land).
-- AND b.elevation_m < 0 ensures only confirmed submarine pixels pass through.
-- NOTE: round(lat/lon, 3) precision is intentional here — this is a pixel-to-pixel
-- match between two high-resolution rasters. Switching to spatial_id (0.25° grid)
-- would broaden the join and add ~2.2M additional rows from unmatched grid cells.
inner join {{ source('med_wind_prod', 'raw_bathymetry') }} b
    on round(c.latitude, 3) = round(b.latitude, 3)
    and round(c.longitude, 3) = round(b.longitude, 3)
    and b.elevation_m < 0  -- Marine pixels only: negative elevation = below sea level

where c.distance_to_coast_km >= 2  -- Filter out invalid data (negative distances)