cat > models/staging/stg_bathymetry.sql << 'EOF'
-- Staging model for bathymetry data
-- Filters to marine cells only and adds depth category
-- Source: ETOPO 2022 (NOAA), resolution ~450m, WGS84

select
    latitude,
    longitude,
    elevation_m,

    -- Depth as positive number for easier interpretation
    abs(elevation_m) as depth_m,

    -- Depth category for turbine type suitability
    case
        when elevation_m > -50  then 'shallow'       -- viable for fixed turbines
        when elevation_m > -200 then 'transitional'  -- viable for floating turbines
        else                         'deep'           -- not viable with current technology
    end as depth_category,

    -- Viability flags
    elevation_m >= -50  as viable_fixed,
    elevation_m >= -200 as viable_floating

from {{ source('med_wind_prod', 'raw_bathymetry') }}
where elevation_m < 0  -- marine cells only
EOF