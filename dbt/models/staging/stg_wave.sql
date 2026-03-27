-- stg_wave.sql
-- Staging model for raw wave data
-- Selects, renames, and standardizes columns from raw_wave_data
-- No business logic — column renaming, unit clarification, and ID generation only
--
-- FIX: spatial_id now uses cast(round(..., 4) as string) hashing to match
--      stg_bathymetry, stg_coastline_distance, and int_site_centers.
--      Previous float64 hashing caused silent join failures.
-- FIX: grid_lat/grid_lon renamed to snap_lat/snap_lon per nomenclature standard.
-- FIX: generate_grid_id macro now used for spatial_id.

select
    -- True primary key for time-series data (Site + Timestamp)
    {{ dbt_utils.generate_surrogate_key(['location_name', 'observation_time']) }} as record_id,

    -- Foreign key to the site location
    {{ dbt_utils.generate_surrogate_key(['location_name']) }} as site_id,
    
    location_name,
    observation_time,

    wave_height,
    wave_direction,
    wave_period,

    -- Snap raw coordinates to the 0.25 degree grid center
    cast(round(floor(latitude  / 0.25) * 0.25 + 0.125, 4) as float64) as snap_lat,
    cast(round(floor(longitude / 0.25) * 0.25 + 0.125, 4) as float64) as snap_lon,

    -- Spatial join key — string-cast to prevent float precision hash drift
    {{ generate_grid_id('latitude', 'longitude') }} as spatial_id,

    extract(year  from observation_time) as year,
    extract(month from observation_time) as month

from {{ source('med_wind_prod', 'raw_wave_data') }}
where wave_height is not null

{% if var('is_test_run', default=false) %}
  and location_name in ('GULF_OF_LION_43.0_4.0', 'GULF_OF_LION_42.75_3.75', 'GULF_OF_LION_42.5_3.5')
  and extract(year from observation_time) = 2023
{% endif %}