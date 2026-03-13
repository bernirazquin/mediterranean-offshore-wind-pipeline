cat > models/staging/stg_wind.sql << 'EOF'
-- Staging model for raw wind data
-- Selects and renames columns from raw_wind_data

select
    location_name,
    latitude,
    longitude,
    observation_time,
    wind_speed_100m,
    wind_direction_100m,
    wind_speed_10m,

    -- Derived fields
    extract(year  from observation_time) as year,
    extract(month from observation_time) as month

from {{ source('med_wind_prod', 'raw_wind_data') }}
where wind_speed_100m is not null
EOF