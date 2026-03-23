-- int_site_spatial_score.sql
-- Owns all spatial scoring logic for each Gulf of Lion site.
-- Consumes int_site_spatial_summary (depth + distance aggregates).
-- Produces one row per site with normalised 0–1 scores.
--
-- Scoring rules:
--   depth_score  : 1.0 at 0m depth,  0.0 at 200m+ (fixed turbine threshold)
--   coast_score  : 1.0 at 0km coast, 0.0 at 200km+ (export cable cost proxy)
--   spatial_score: simple average of the two — equal weighting by default
--
-- This model is the single source of truth for spatial scoring.
-- If the depth/distance thresholds need to change, change them here only.

with base as (
    select
        site_name,
        spatial_id,
        center_lat,
        center_lon,
        depth_m,
        depth_category,
        turbine_type,
        distance_to_coast_km,
        distance_category,
        sample_count
    from {{ ref('int_site_spatial_summary') }}
),

scored as (
    select
        *,
        -- Depth score: shallow favoured for fixed turbine economics
        round(1 - least(depth_m, 200) / 200, 4)              as depth_score,

        -- Coast score: nearshore favoured for export cable length
        round(1 - least(distance_to_coast_km, 200) / 200, 4) as coast_score

    from base
)

select
    site_name,
    spatial_id,
    center_lat,
    center_lon,
    depth_m,
    depth_category,
    turbine_type,
    distance_to_coast_km,
    distance_category,
    sample_count,
    depth_score,
    coast_score,
    -- Composite spatial score — equal weight between depth and coast
    round((depth_score + coast_score) / 2, 4) as spatial_score

from scored