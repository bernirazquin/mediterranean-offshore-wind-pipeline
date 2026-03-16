-- Seed-like model that defines the 14 site center coordinates
-- In a scaled version (200+ sites) this would be replaced by a dbt seed CSV
select
    site_name,
    polygon_name,
    geometry,
    case site_name
        when 'ALBORAN_SEA'        then 36.0
        when 'GULF_OF_VALENCIA'   then 39.5
        when 'EBRO_DELTA'         then 40.7
        when 'COSTA_BRAVA'        then 42.1
        when 'GULF_OF_LYON'       then 43.0
        when 'BALEARIC_SEA'       then 39.0
        when 'TYRRHENIAN_SEA'     then 40.0
        when 'STRAIT_OF_SICILY'   then 37.3
        when 'NORTH_ADRIATIC_SEA' then 44.5
        when 'IONIAN_SEA'         then 38.0
        when 'AEGEAN_SEA'         then 37.5
        when 'LIBYAN_COAST'       then 33.0
        when 'LEVANTINE_SEA'      then 34.0
        when 'CYPRUS_COAST'       then 35.0
    end as center_lat,
    case site_name
        when 'ALBORAN_SEA'        then -4.0
        when 'GULF_OF_VALENCIA'   then -0.1
        when 'EBRO_DELTA'         then  0.9
        when 'COSTA_BRAVA'        then  3.3
        when 'GULF_OF_LYON'       then  4.0
        when 'BALEARIC_SEA'       then  2.5
        when 'TYRRHENIAN_SEA'     then 12.0
        when 'STRAIT_OF_SICILY'   then 12.8
        when 'NORTH_ADRIATIC_SEA' then 13.0
        when 'IONIAN_SEA'         then 18.0
        when 'AEGEAN_SEA'         then 25.0
        when 'LIBYAN_COAST'       then 20.0
        when 'LEVANTINE_SEA'      then 30.0
        when 'CYPRUS_COAST'       then 34.0
    end as center_lon
from {{ ref('stg_site_boundaries') }}