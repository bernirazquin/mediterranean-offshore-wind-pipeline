cat > models/staging/stg_wave.sql << 'EOF'
-- Staging model for raw wave data
-- Selects and renames columns from raw_wave_data
-- No business logic — just cleaning and standardization

select
    location_name,
    latitude,
    longitude,
    observation_time,
    wave_height,
    wave_direction,
    wave_period,

    -- Derived fields
    extract(year  from observation_time) as year,
    extract(month from observation_time) as month

from {{ source('med_wind_prod', 'raw_wave_data') }}
where wave_height is not null
EOF