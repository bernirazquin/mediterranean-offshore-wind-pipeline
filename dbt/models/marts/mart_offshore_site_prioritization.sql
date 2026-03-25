-- mart_offshore_site_prioritization.sql
-- Final deliverable: ranked list of viable offshore wind sites.
-- Pure presentation layer — no business logic except manual exclusions.
--
-- Manual exclusions applied here (not in intermediate layer):
--   Sites that pass all quantitative gates but plot on land in QGIS
--   and Looker Studio are excluded via the manually_excluded_sites seed.
--   This is the correct architectural layer for override decisions.
--   Excluded sites remain visible in mart_offshore_site_gis with
--   viability_flag = 'excluded: manual review — centroid plots on land'.
--
-- All scoring and physical gates live in int_site_composite_score.

with excluded as (
    -- Seed-based manual override: visually confirmed land-centroid misplacements
    -- that pass quantitative marine gates but plot on land in QGIS/Looker Studio.
    -- To reinstate a site: remove its row from seeds/manually_excluded_sites.csv
    select site_name from {{ ref('manually_excluded_sites') }}
)

select
    ROW_NUMBER() OVER (
        ORDER BY final_score DESC, avg_wind_speed_ms DESC, site_name ASC
    ) as site_rank,
    cs.*
from {{ ref('int_site_composite_score') }} cs
where cs.site_name not in (select site_name from excluded)