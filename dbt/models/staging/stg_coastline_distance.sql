-- Staging model for coastline distance data
-- Filters out land cells via inner join with bathymetry
-- Source: Natural Earth 1:10m coastline, scipy distance transform, WGS84

select
    c.latitude,
    c.longitude,
    c.distance_to_coast_km,

    -- Distance category for economic viability assessment
    case
        when c.distance_to_coast_km < 50  then 'nearshore'   -- lowest installation cost
        when c.distance_to_coast_km < 100 then 'midshore'    -- viable with subsidies
        else                                   'offshore'    -- high cost, large projects only
    end as distance_category

from {{ source('med_wind_prod', 'raw_coastline_distance') }} c
-- inner join with bathymetry filters out land cells
-- (raw_coastline_distance contains ~39M land cells)
inner join {{ source('med_wind_prod', 'raw_bathymetry') }} b
    on round(c.latitude,  3) = round(b.latitude,  3)
    and round(c.longitude, 3) = round(b.longitude, 3)