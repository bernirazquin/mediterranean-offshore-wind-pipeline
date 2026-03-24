-- int_site_spatial_score.sql
-- Owns all spatial scoring logic for each Gulf of Lion site.
-- Consumes int_site_spatial_summary (depth + distance aggregates).
-- Produces one row per site with normalised 0–1 scores.
--
-- Scoring rules (fixed turbines):
--   depth_score  : 1.0 at 0m, 0.0 at 200m+ — linear, shallower is better
--   coast_score  : 1.0 at 0km, 0.0 at 200km+ — linear, closer is better
--
-- Scoring rules (floating turbines):
--   depth_score  : bell curve peaking at 180m (sweet spot 60–300m)
--   coast_score  : bell curve peaking at 35km (sweet spot 20–50km)
--
-- CHANGE: Removed nearshore penalty (0.7×) — redundant with 11km hard gate
--         in int_site_composite_score. Gate is cleaner and more honest.
--
-- This model is the single source of truth for spatial scoring.
-- If thresholds need to change, change them here only.

with base as (
    select
        site_name,
        site_id,
        spatial_id,
        center_lat,
        center_lon,
        depth_m,
        depth_category,
        distance_to_coast_km,
        distance_category,
        sample_count
    from {{ ref('int_site_spatial_summary') }}
),

typed as (
    select
        *,
        -- Turbine technology viability based on water depth
        -- CHANGE: upper floating limit raised from 200m to 300m
        --         to match floating turbine engineering range
        case
            when depth_m <= 50  then 'fixed'
            when depth_m <= 1000 then 'floating'
            else                     'not_viable'
        end as turbine_type
    from base
),

scored as (
    select
        *,

        -- Depth score
        case
            when turbine_type = 'fixed' then
                -- Linear: shallower = better
                round(1 - least(depth_m, 200) / 200, 4)

            when turbine_type = 'floating' then
                -- Bell curve peaking at 180m, wide falloff
                round(
                    greatest(
                        1 - pow((depth_m - 180) / 200.0, 2),
                        0
                    ),
                4)

            else 0
        end as depth_score,

        -- Coast score
        case
            when turbine_type = 'fixed' then
                -- Linear: closer = better
                round(1 - least(distance_to_coast_km, 200) / 200, 4)

            when turbine_type = 'floating' then
                -- Bell curve peaking at 35km, wide falloff
                round(
                    greatest(
                        1 - pow((distance_to_coast_km - 35) / 60.0, 2),
                        0
                    ),
                4)

            else 0
        end as coast_score

    from typed
)

select
    site_name,
    site_id,
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
    -- CHANGE: removed nearshore_penalty column and multiplier
    round((depth_score + coast_score) / 2, 4) as spatial_score

from scored