-- int_site_wave_score.sql
-- Owns all wave scoring logic for each Gulf of Lion site.
-- Consumes int_site_wave_summary (aggregated wave statistics).
-- Joins int_site_spatial_score to get turbine_type for type-aware scoring.
-- Produces one row per site with a normalised 0–1 wave score.
--
-- Scoring rules:
--   fixed turbines    : wave_score hits 0 at 4m avg wave height
--   floating turbines : wave_score hits 0 at 6m avg wave height
--                       floating structures are engineered for rougher seas
--
-- survivability_class: evaluates extreme conditions against structural limits.
-- sea_state_class    : evaluates wave period for maintenance vessel operability.
--
-- This model is the single source of truth for wave scoring.

with base as (
    select
        w.site_id,
        w.site_name,
        w.avg_wave_height_m,
        w.max_wave_height_m,
        w.avg_wave_period_s,
        sp.turbine_type
    from {{ ref('int_site_wave_summary') }} w
    inner join {{ ref('int_site_spatial_score') }} sp
        on w.site_name = sp.site_name
),

scored as (
    select
        *,
        -- Wave score: threshold depends on turbine type
        case
            when turbine_type = 'fixed' then
                -- Fixed: 0m = 1.0, linearly drops to 0.0 at 4m
                round(greatest(1.0 - (avg_wave_height_m / 4.0), 0.0), 4)

            when turbine_type = 'floating' then
                -- Floating: 0m = 1.0, linearly drops to 0.0 at 6m
                round(greatest(1.0 - (avg_wave_height_m / 6.0), 0.0), 4)

            else 0
        end as wave_score,

        -- Survivability: max wave height structural limits
        case
            when max_wave_height_m < 8  then 'high'
            when max_wave_height_m < 12 then 'medium'
            else                             'low'
        end as survivability_class,

        -- Sea state: wave period operability for maintenance vessels
        case
            when avg_wave_period_s < 6  then 'choppy'
            when avg_wave_period_s <= 10 then 'moderate'
            else                              'swell'
        end as sea_state_class

    from base
)

select
    site_id,
    site_name,
    turbine_type,
    avg_wave_height_m,
    max_wave_height_m,
    avg_wave_period_s,
    wave_score,
    survivability_class,
    sea_state_class

from scored