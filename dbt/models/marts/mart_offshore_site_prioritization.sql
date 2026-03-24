-- mart_offshore_site_prioritization.sql
-- Final deliverable: ranked list of viable offshore wind sites.
-- This model contains NO business logic — it is a pure presentation layer.
--
-- All scoring, filtering, and joining happens in:
--   int_site_spatial_score    → depth_score, coast_score, spatial_score, turbine_type
--   int_site_wind_score       → wind_score, wind_potential_class
--   int_site_wave_score       → wave_score, survivability_class, sea_state_class
--   int_site_composite_score  → final_score (40/40/20 Spatial/Wind/Wave)
--                               with survivability multiplier applied
--
-- Hard gates applied in int_site_composite_score:
--   depth_m >= 10, distance_to_coast_km >= 11, depth_m <= 1000
--   turbine_type != 'not_viable'
--
-- This mart is the decision-making layer — only engineeringly viable sites.
-- For the full 111-point export for GIS analysis see mart_offshore_site_gis.sql

select
    ROW_NUMBER() OVER (
        ORDER BY final_score DESC, avg_wind_speed_ms DESC, site_name ASC
    ) as site_rank,
    *
from {{ ref('int_site_composite_score') }}