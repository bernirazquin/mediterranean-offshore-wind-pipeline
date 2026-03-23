-- int_site_composite_score.sql
-- Joins spatial, wind, and wave scores into a single composite score per site.
-- This is the deepest layer of business logic — the mart reads from here only.

with spatial as (
    select * from {{ ref('int_site_spatial_score') }}
    where turbine_type != 'not_viable'
),

wind as (
    select * from {{ ref('int_site_wind_score') }}
),

wave as (
    select * from {{ ref('int_site_wave_score') }}
),

joined as (
    select
        -- Identity
        sp.site_name,
        sp.spatial_id,
        sp.center_lat,
        sp.center_lon,

        -- Spatial profile & scores
        sp.depth_m,
        sp.turbine_type,
        sp.distance_to_coast_km,
        sp.spatial_score,

        -- Wind profile & scores
        w.avg_wind_speed_ms,
        w.wind_power_potential_index,
        w.wind_potential_class,
        w.wind_score,

        -- Wave profile & scores
        wv.avg_wave_height_m,
        wv.max_wave_height_m,
        wv.avg_wave_period_s,    -- Added for engineering context
        wv.sea_state_class,      -- Added for operational filtering
        wv.survivability_class,
        wv.wave_score,

        -- Composite score: Spatial (30%), Wind (50%), Wave (20%)
        round(
            (0.30 * sp.spatial_score)
            + (0.50 * w.wind_score)
            + (0.20 * wv.wave_score),
        4) as final_score

    from spatial sp
    -- Inner join: site must have all three data sources to be ranked
    inner join wind w on sp.site_name = w.site_name
    inner join wave wv on sp.site_name = wv.site_name
)

select * from joined
where depth_m > 5 AND depth_m <= 200  -- Final viability filter for fixed turbines only; see turbine_type logic above for exclusions turbines