-- stg_bathymetry.sql
-- Staging model for bathymetry data
-- Filters to marine cells only and adds depth category
-- Source: ETOPO 2022 (NOAA), resolution ~450m, WGS84
-- Snapping high-res raster data to the project's 0.25 deg grid

select
    latitude,
    longitude,
    elevation_m,
    abs(elevation_m) as depth_m,

    -- Snapping logic (The "Join Optimizer")
    cast(floor(latitude / 0.25) * 0.25 + 0.125 as float64) as grid_lat,
    cast(floor(longitude / 0.25) * 0.25 + 0.125 as float64) as grid_lon,

    -- Surrogate key for the grid cell
    -- Standardized Spatial ID

    {{ dbt_utils.generate_surrogate_key([
        'cast(round(floor(latitude / 0.25) * 0.25 + 0.125, 4) as string)',
        'cast(round(floor(longitude / 0.25) * 0.25 + 0.125, 4) as string)'
    ]) }} as spatial_id

    case
        when elevation_m > -50  then 'shallow'
        when elevation_m > -200 then 'transitional'
        else                         'deep'
    end as depth_category

from {{ source('med_wind_prod', 'raw_bathymetry') }}
where elevation_m < 0 -- Marine cells only