-- Derives the 111 Gulf of Lion grid point centers directly from the site keys
-- in the wind data. No coordinates are hardcoded — lat/lon are parsed from the
-- site key itself (e.g. GULF_OF_LION_41.5_3.25 → lat 41.5, lon 3.25).
--
-- Replaces the old int_site_centers which hardcoded 14 Mediterranean site
-- coordinates in a CASE WHEN block. In the new design, coordinates are
-- encoded in the KV store key and flow through to raw_wind_data automatically.
--
-- Dependencies: stg_wind
-- Used by:      int_site_spatial_samples

select distinct
    location_name                                                  as site_name,
    CAST(SPLIT(location_name, '_')[OFFSET(3)] AS FLOAT64)         as center_lat,
    CAST(SPLIT(location_name, '_')[OFFSET(4)] AS FLOAT64)         as center_lon
from {{ ref('stg_wind') }}
where location_name like 'GULF_OF_LION_%'