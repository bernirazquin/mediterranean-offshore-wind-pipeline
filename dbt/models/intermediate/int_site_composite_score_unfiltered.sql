-- int_site_composite_score_unfiltered.sql
-- Identical to int_site_composite_score but with no hard gates applied.
-- Used exclusively by mart_offshore_site_gis for GIS export.
-- Do NOT use this model for scoring or decision making.
--
-- All 102 marine grid points flow through here regardless of depth,
-- distance, or turbine viability. Manually excluded sites are flagged
-- but still present — GIS analysts need to see them.

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

-- Manual exclusion list: sites flagged via visual inspection in QGIS
-- and Looker Studio. Included here so the GIS mart can surface the flag.
excluded as (
    select site_name from {{ ref('manually_excluded_sites') }}
),

joined as (
    select
        sp.site_name,
        sp.site_id,
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
        4) as raw_final_score,

        -- Flag for manual exclusion — carried through to viability_flag below
        case when sp.site_name in (select site_name from excluded)
            then true else false
        end as is_manually_excluded

    from spatial sp
    inner join wind w  on sp.site_id = w.site_id
    inner join wave wv on sp.site_id = wv.site_id
)

select
    site_name,
    site_id,
    spatial_id,
    center_lat,
    center_lon,
    depth_m,
    turbine_type,
    distance_to_coast_km,
    spatial_score,
    avg_wind_speed_ms,
    wind_power_potential_index,
    wind_potential_class,
    wind_score,
    avg_wave_height_m,
    max_wave_height_m,
    avg_wave_period_s,
    sea_state_class,
    survivability_class,
    wave_score,
    survivability_multiplier,
    raw_final_score,
    round(raw_final_score * survivability_multiplier, 4) as final_score,

    -- Viability flag: tells GIS analyst why a site was excluded
    -- from the decision-making mart. Manual review checked first so
    -- it is always visible even if the site also fails a physical gate.
    case
        when is_manually_excluded        then 'excluded: manual review — centroid plots on land'
        when depth_m < 10                then 'excluded: depth < 10m'
        when depth_m > 1000              then 'excluded: depth > 1000m'
        when turbine_type = 'not_viable' then 'excluded: not viable'
        when turbine_type = 'fixed'
             and distance_to_coast_km < 11 then 'excluded: fixed < 11km coast'
        when turbine_type = 'floating'
             and distance_to_coast_km < 5  then 'excluded: floating < 5km coast'
        else                                    'viable'
    end as viability_flag

from joined