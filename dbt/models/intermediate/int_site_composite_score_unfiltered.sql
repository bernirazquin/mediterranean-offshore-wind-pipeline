-- int_site_composite_score_unfiltered.sql
-- Identical to int_site_composite_score but with no hard gates applied.
-- Used exclusively by mart_offshore_site_gis for GIS export.
-- Do NOT use this model for scoring or decision making.
--
-- All 111 grid points flow through here regardless of depth,
-- distance, or turbine viability.

with spatial as (
    -- NOTE: not_viable sites included intentionally for GIS reference
    select * from {{ ref('int_site_spatial_score') }}
),

wind as (
    select * from {{ ref('int_site_wind_score') }}
),

wave as (
    select * from {{ ref('int_site_wave_score') }}
),

joined as (
    select
        sp.site_name,
        sp.spatial_id,
        sp.center_lat,
        sp.center_lon,
        sp.depth_m,
        sp.turbine_type,
        sp.distance_to_coast_km,
        sp.spatial_score,
        w.avg_wind_speed_ms,
        w.wind_power_potential_index,
        w.wind_potential_class,
        w.wind_score,
        wv.avg_wave_height_m,
        wv.max_wave_height_m,
        wv.avg_wave_period_s,
        wv.sea_state_class,
        wv.survivability_class,
        wv.wave_score,
        case
            when wv.survivability_class = 'high'   then 1.0
            when wv.survivability_class = 'medium' then 0.9
            else                                        0.7
        end as survivability_multiplier,
        round(
            (0.40 * sp.spatial_score)
            + (0.40 * w.wind_score)
            + (0.20 * wv.wave_score),
        4) as raw_final_score

    from spatial sp
    inner join wind w  on sp.site_name = w.site_name
    inner join wave wv on sp.site_name = wv.site_name
)

select
    *,
    round(raw_final_score * survivability_multiplier, 4) as final_score,
    -- Viability flag: tells GIS analyst why a site was excluded
    -- from the decision-making mart
    case
        when depth_m < 10                then 'excluded: depth < 10m'
        when distance_to_coast_km < 11   then 'excluded: distance < 11km'
        when depth_m > 300               then 'excluded: depth > 300m'
        when turbine_type = 'not_viable' then 'excluded: not viable'
        else                                  'viable'
    end as viability_flag

from joined