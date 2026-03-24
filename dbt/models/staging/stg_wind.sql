-- stg_wind.sql
-- Staging model for raw wind data
-- Selects, renames, and standardizes columns from raw_wind_data
-- No business logic — column renaming, unit clarification, and ID generation only
--
-- FIX: spatial_id now uses cast(round(..., 4) as string) hashing to match
--      stg_bathymetry, stg_coastline_distance, and int_site_centers.
--      Previous float64 hashing caused silent join failures.
-- FIX: grid_lat/grid_lon renamed to snap_lat/snap_lon per nomenclature standard.
-- FIX: wind_speed_100m renamed to wind_speed_ms and converted from km/h to m/s.
--      Source raw_wind_data stores wind speed in km/h — dividing by 3.6 converts
--      to m/s which is the standard unit for all downstream scoring.
-- FIX: location_name retained as-is for coord parsing in int_site_centers,
--      but site_id is now the surrogate key generated from it.
-- FIX: generate_grid_id macro now used for spatial_id.

select
    -- True primary key for time-series data (Site + Timestamp)
    {{ dbt_utils.generate_surrogate_key(['location_name', 'observation_time']) }} as record_id,

    -- Foreign key to the site location
    {{ dbt_utils.generate_surrogate_key(['location_name']) }} as site_id,

    location_name,
    observation_time,

    -- Convert from km/h to m/s (source data is in km/h)
    round(wind_speed_100m / 3.6, 4)     as wind_speed_ms,
    wind_direction_100m                  as wind_direction,

    -- Snap raw coordinates to the 0.25 degree grid center
    cast(round(floor(latitude  / 0.25) * 0.25 + 0.125, 4) as float64) as snap_lat,
    cast(round(floor(longitude / 0.25) * 0.25 + 0.125, 4) as float64) as snap_lon,

    -- Spatial join key — string-cast to prevent float precision hash drift
    {{ generate_grid_id('latitude', 'longitude') }} as spatial_id,

    extract(year  from observation_time) as year,
    extract(month from observation_time) as month

from {{ source('med_wind_prod', 'raw_wind_data') }}
where wind_speed_100m is not null