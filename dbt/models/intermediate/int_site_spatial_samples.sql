-- Compute the sampling zone per site: buffer ∩ IHO polygon
with sampling_zones as (
    select
        site_name,
        polygon_name,
        center_lat,
        center_lon,
        ST_INTERSECTION(
            ST_BUFFER(ST_GEOGPOINT(center_lon, center_lat), 100000), -- 100km buffer in meters
            geometry
        ) as sampling_zone
    from {{ ref('int_site_centers') }}
),

-- Sample all raster cells that fall within each site's sampling zone
spatial_samples as (
    select
        sz.site_name,
        sz.center_lat,
        sz.center_lon,
        b.latitude,
        b.longitude,
        b.depth_m,
        b.depth_category,
        b.viable_fixed,
        b.viable_floating,
        cd.distance_to_coast_km,
        cd.distance_category,
        ST_DISTANCE(
            ST_GEOGPOINT(b.longitude, b.latitude),
            ST_GEOGPOINT(sz.center_lon, sz.center_lat)
        ) / 1000 as dist_to_center_km
    from sampling_zones sz
    join {{ ref('stg_bathymetry') }} b
        on ST_INTERSECTS(sz.sampling_zone, ST_GEOGPOINT(b.longitude, b.latitude))
    join {{ ref('stg_coastline_distance') }} cd
        on ROUND(b.latitude, 3) = ROUND(cd.latitude, 3)
        and ROUND(b.longitude, 3) = ROUND(cd.longitude, 3)
)

select * from spatial_samples
