-- stg_wind.sql
-- Staging model for raw wind data
-- Selects and renames columns from raw_wind_data
--Added grid-snapping and surrogate keys for join optimization

select
    -- Generate a Unique ID for the specific location name
    {{ dbt_utils.generate_surrogate_key(['location_name']) }} as site_id,
    
    location_name,
    observation_time,
    wind_speed_100m,
    wind_direction_100m,
    
    -- Snap to the 0.25 degree grid center for spatial joining
    -- This ensures a coordinate like 41.13 becomes 41.125
    cast(floor(latitude / 0.25) * 0.25 + 0.125 as float64) as grid_lat,
    cast(floor(longitude / 0.25) * 0.25 + 0.125 as float64) as grid_lon,

    -- Create a spatial_id to join with bathymetry/coastline later
    {{ dbt_utils.generate_surrogate_key([
        'cast(floor(latitude / 0.25) * 0.25 + 0.125 as float64)',
        'cast(floor(longitude / 0.25) * 0.25 + 0.125 as float64)'
    ]) }} as spatial_id,

    extract(year from observation_time) as year,
    extract(month from observation_time) as month

from {{ source('med_wind_prod', 'raw_wind_data') }}
where wind_speed_100m is not null