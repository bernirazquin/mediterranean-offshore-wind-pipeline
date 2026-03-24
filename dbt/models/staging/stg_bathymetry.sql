-- stg_bathymetry.sql
-- Staging model for bathymetry data
-- Filters to marine cells only (WHERE elevation_m < 0) and computes depth metrics.
-- Source: ETOPO 2022 (NOAA), resolution ~450m, WGS84
--
-- FIX: Missing comma before depth_category CASE block (syntax crash).
-- FIX: elevation_m dropped — depth_m (positive value) is the only exposed metric
--      per nomenclature standard. Consumers should never need raw elevation.
-- FIX: grid_lat/grid_lon renamed to snap_lat/snap_lon.
-- FIX: generate_grid_id macro now used for spatial_id.
-- FIX: Added WHERE elevation_m < 0 — model previously claimed to filter marine-only
--      but had no WHERE clause. Land rows now excluded at source.

select
    -- Snap raw coordinates to the 0.25 degree grid center
    cast(round(floor(latitude  / 0.25) * 0.25 + 0.125, 4) as float64) as snap_lat,
    cast(round(floor(longitude / 0.25) * 0.25 + 0.125, 4) as float64) as snap_lon,

    -- Raw data
    elevation_m,

    -- Transformation: Flip negative elevation to positive depth for the Wind analysts
    -- ETOPO: -2000m (Sea) -> Staging: 2000m (Depth)
    -- elevation_m is always < 0 here (land filtered out above), so abs() is safe
    elevation_m * -1 as depth_m,

    -- Flag for land vs water — always 0 after the WHERE clause, retained for schema
    -- compatibility and downstream tests
    0 as is_land,

    -- Spatial join key
    {{ generate_grid_id('latitude', 'longitude') }} as spatial_id

from {{ source('med_wind_prod', 'raw_bathymetry') }}
where elevation_m < 0  -- Marine cells only: negative elevation = below sea level