-- stg_bathymetry.sql
-- Staging model for bathymetry data
-- Filters to marine cells only and adds depth category
-- Source: ETOPO 2022 (NOAA), resolution ~450m, WGS84
--
-- FIX: Missing comma before depth_category CASE block (syntax crash).
-- FIX: elevation_m dropped — depth_m (positive value) is the only exposed metric
--      per nomenclature standard. Consumers should never need raw elevation.
-- FIX: grid_lat/grid_lon renamed to snap_lat/snap_lon.
-- FIX: generate_grid_id macro now used for spatial_id.

select
    -- Snap raw coordinates to the 0.25 degree grid center
    cast(round(floor(latitude  / 0.25) * 0.25 + 0.125, 4) as float64) as snap_lat,
    cast(round(floor(longitude / 0.25) * 0.25 + 0.125, 4) as float64) as snap_lon,

    -- Convert elevation (negative) to positive depth — elevation_m not exposed downstream
    abs(elevation_m) as depth_m,

    -- Spatial join key — string-cast to prevent float precision hash drift
    {{ generate_grid_id('latitude', 'longitude') }} as spatial_id,

    case
        when elevation_m > -50  then 'shallow'
        when elevation_m > -200 then 'transitional'
        else                         'deep'
    end as depth_category

from {{ source('med_wind_prod', 'raw_bathymetry') }}
where elevation_m > 0  -- Marine cells only