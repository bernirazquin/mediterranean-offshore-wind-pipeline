-- int_site_spatial_summary.sql
-- One row per Gulf of Lion grid point summarising static spatial characteristics
-- Upstream: int_site_spatial_samples

select
    site_name,
    spatial_id,
    center_lat,
    center_lon,
    depth_m,
    depth_min_m,
    depth_max_m,
    depth_category,
    distance_to_coast_km,
    distance_min_km,
    distance_category,
    sample_count,
    marine_coverage_pct

from {{ ref('int_site_spatial_samples') }}
where depth_m is not null
  -- If more than 10% of the grid cell is land, we evict it.
  and marine_coverage_pct >= 0.90