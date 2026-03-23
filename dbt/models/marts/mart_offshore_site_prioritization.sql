-- mart_offshore_site_prioritization.sql
-- Final deliverable: ranked list of viable offshore wind sites.
-- This model contains NO business logic — it is a pure presentation layer.
--
-- All scoring, filtering, and joining happens in:
--   int_site_spatial_score    → depth_score, coast_score, spatial_score
--   int_site_wind_score       → wind_score, wind_potential_class
--   int_site_composite_score  → final_score (30/50/20 split (Spatial/Wind/Wave))
--
-- This model only adds: site_rank via RANK() window function.

select
    -- Ranking
    rank() over (order by final_score desc) as site_rank,

    -- All scored fields from the composite intermediate
    *

from {{ ref('int_site_composite_score') }}
order by site_rank