-- stg_wave.sql
-- Staging model for raw wave data
-- Selects and renames columns from raw_wave_data
-- No business logic — just cleaning and standardization
-- Professional Fix: Standardized grid-snapping and surrogate keys to match stg_wind

select
    -- Unique ID for the specific location name
    {{ dbt_utils.generate_surrogate_key(['location_name']) }} as site_id,
    
    location_name,
    observation_time,
    wave_height,
    wave_direction,
    wave_period,

    -- Snap to the 0.25 degree grid center
    cast(floor(latitude / 0.25) * 0.25 + 0.125 as float64) as grid_lat,
    cast(floor(longitude / 0.25) * 0.25 + 0.125 as float64) as grid_lon,

    -- Create the same spatial_id used in bathymetry and wind
    {{ dbt_utils.generate_surrogate_key([
        'cast(floor(latitude / 0.25) * 0.25 + 0.125 as float64)',
        'cast(floor(longitude / 0.25) * 0.25 + 0.125 as float64)'
    ]) }} as spatial_id,

    extract(year from observation_time) as year,
    extract(month from observation_time) as month

from {{ source('med_wind_prod', 'raw_wave_data') }}
where wave_height is not null