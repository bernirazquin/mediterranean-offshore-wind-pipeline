-- mart_offshore_site_gis.sql
-- Full 111-point export for GIS analysis and land mask verification.
-- This model contains NO business logic — it is a pure presentation layer.
--
-- IMPORTANT: This mart bypasses all hard gates intentionally.
-- Points here may be:
--   - Too shallow (depth < 10m) — potentially inland
--   - Too close to shore (distance < 11km)
--   - Beyond floating turbine range (depth > 300m)
--   - not_viable turbine type
--
-- Purpose: let GIS analysts apply a high-res land mask and verify which
-- points are true errors vs resolution artifacts of the 0.25° grid.
-- Do NOT use this mart for site ranking or decision making.
--
-- Scores are still computed and visible so analysts can cross-reference
-- with the filtered mart and understand why sites were eliminated.

select
    -- Only rank viable sites, excluded sites get null
    case
        when viability_flag = 'viable' then
            ROW_NUMBER() OVER (
                PARTITION BY viability_flag = 'viable'
                ORDER BY final_score DESC, avg_wind_speed_ms DESC, site_name ASC
            )
        else null
    end as site_rank,
    *
from {{ ref('int_site_composite_score_unfiltered') }}
order by viability_flag, final_score desc