-- Staging model for site boundaries
-- Converts WKT geometry string to BigQuery GEOGRAPHY type
-- make_valid fixes self-intersecting edges from the IHO shapefile
-- Source: IHO Sea Areas v3 (Marine Regions), exported via QGIS
-- Balearic Sea merged into Western Basin to avoid splitting coastal sites

select
    site_name,
    polygon_name,
    ST_GEOGFROMTEXT(geometry_wkt, make_valid => TRUE) as geometry

from {{ source('med_wind_prod', 'raw_site_boundaries') }}