# Data Validation & Scoring Sanity Checklist

**Project:** Mediterranean Offshore Wind Suitability Analysis  
**Region:** Gulf of Lion  
**Pipeline:** dbt + BigQuery  
**Last updated:** 2026-03

This document is the single source of truth for validating that the pipeline data is accurate and the scoring makes physical sense. Run all checks after every `dbt build` and before any merge to main.

---

## 1. Row Count Checks

Every site should be traceable from source to mart. Any drop must be explainable.

### 1.1 — Total sites at each layer

```sql
-- Should be 102 (9 land cells filtered at int_site_centers via bathymetry join)
SELECT COUNT(DISTINCT site_name) AS site_count
FROM `med-offshore-test.wind_intermediate.int_site_centers`;

-- Should be 102 (all marine points scored, no drops from joins)
SELECT COUNT(*) AS site_count
FROM `med-offshore-test.wind_intermediate.int_site_composite_score_unfiltered`;

-- Should be < 102 (viable sites only after hard gates)
SELECT COUNT(*) AS site_count
FROM `med-offshore-test.wind_intermediate.int_site_composite_score`;

-- Should match composite score count
SELECT COUNT(*) AS site_count
FROM `med-offshore-test.wind_marts.mart_offshore_site_prioritization`;

-- Should be 102 (full export for GIS)
SELECT COUNT(*) AS site_count
FROM `med-offshore-test.wind_marts.mart_offshore_site_gis`;
```

**Note:** The original wind grid had 111 points. 9 were confirmed land cells with zero marine bathymetry samples and are excluded at `int_site_centers`. This is expected and correct.

### 1.2 — Viability breakdown (understand what was eliminated and why)

```sql
SELECT
    viability_flag,
    COUNT(*) AS site_count
FROM `med-offshore-test.wind_marts.mart_offshore_site_gis`
GROUP BY 1
ORDER BY 1;
```

**Expected viability_flag values:**
- `viable` — passed all gates, included in decision mart
- `excluded: depth < 10m` — too shallow, likely coastal/inland resolution artifact
- `excluded: depth > 1000m` — beyond floating turbine engineering range
- `excluded: not viable` — turbine_type = not_viable
- `excluded: fixed < 11km coast` — fixed turbine too close to shore
- `excluded: floating < 5km coast` — floating turbine too close to shore

### 1.3 — Turbine type distribution

```sql
SELECT
    turbine_type,
    COUNT(*) AS site_count,
    ROUND(AVG(depth_m), 2) AS avg_depth_m,
    ROUND(MIN(depth_m), 2) AS min_depth_m,
    ROUND(MAX(depth_m), 2) AS max_depth_m
FROM `med-offshore-test.wind_intermediate.int_site_composite_score_unfiltered`
GROUP BY 1
ORDER BY 1;
```

**Expected:**
- `fixed`: all rows depth_m <= 50
- `floating`: all rows depth_m > 50 and <= 1000
- `not_viable`: all rows depth_m > 1000
- No nulls in turbine_type

### 1.4 — GIS mart ranking check

```sql
-- Viable sites should have a rank, excluded sites should have null
SELECT
    viability_flag,
    COUNT(*) AS total,
    COUNTIF(site_rank IS NULL) AS null_rank,
    COUNTIF(site_rank IS NOT NULL) AS has_rank
FROM `med-offshore-test.wind_marts.mart_offshore_site_gis`
GROUP BY 1
ORDER BY 1;
```

**Expected:** Only `viable` sites have a rank. All excluded sites show null.

---

## 2. Physical Sanity Checks

### 2.1 — Coordinate bounds (Gulf of Lion)

```sql
SELECT
    COUNT(*) AS total_sites,
    COUNTIF(center_lat BETWEEN 41.0 AND 44.0) AS lat_in_bounds,
    COUNTIF(center_lon BETWEEN 2.0 AND 6.5)   AS lon_in_bounds,
    MIN(center_lat) AS min_lat,
    MAX(center_lat) AS max_lat,
    MIN(center_lon) AS min_lon,
    MAX(center_lon) AS max_lon
FROM `med-offshore-test.wind_intermediate.int_site_composite_score_unfiltered`;
```

**Expected:** All sites within Gulf of Lion bounds. Any site outside is a data error.

### 2.2 — Depth values are positive and plausible

```sql
SELECT
    COUNT(*) AS total,
    COUNTIF(depth_m < 0)    AS negative_depths,
    COUNTIF(depth_m = 0)    AS zero_depths,
    COUNTIF(depth_m > 3000) AS implausibly_deep,
    MIN(depth_m)            AS min_depth,
    MAX(depth_m)            AS max_depth,
    ROUND(AVG(depth_m), 2)  AS avg_depth
FROM `med-offshore-test.wind_intermediate.int_site_composite_score_unfiltered`;
```

**Expected:** No negative depths. No zeros. Max depth plausible for Mediterranean (~2800m).

### 2.3 — Distance to coast is plausible

```sql
SELECT
    COUNT(*) AS total,
    COUNTIF(distance_to_coast_km <= 0)   AS zero_or_negative,
    COUNTIF(distance_to_coast_km > 200)  AS implausibly_far,
    MIN(distance_to_coast_km)            AS min_dist,
    MAX(distance_to_coast_km)            AS max_dist,
    ROUND(AVG(distance_to_coast_km), 2)  AS avg_dist
FROM `med-offshore-test.wind_intermediate.int_site_composite_score_unfiltered`;
```

**Expected:** All values > 0. Nothing over ~200km.

### 2.4 — Gate boundary inspection (sites just above the cutoff)

These are the most likely resolution artifacts — sites that barely passed the gates.

```sql
SELECT
    site_name,
    center_lat,
    center_lon,
    depth_m,
    turbine_type,
    distance_to_coast_km,
    final_score,
    viability_flag
FROM `med-offshore-test.wind_marts.mart_offshore_site_gis`
WHERE viability_flag = 'viable'
  AND (
      depth_m BETWEEN 10 AND 20
      OR (turbine_type = 'fixed'    AND distance_to_coast_km BETWEEN 11 AND 15)
      OR (turbine_type = 'floating' AND distance_to_coast_km BETWEEN 5  AND 10)
  )
ORDER BY distance_to_coast_km ASC;
```

**Expected:** Review each site manually on the GIS map. Sites close to their gate threshold are highest risk for being resolution artifacts. Cross-reference with QGIS land mask verification.

---

## 3. Score Distribution Checks

### 3.1 — Score distribution per dimension

```sql
SELECT
    ROUND(MIN(spatial_score), 3)    AS spatial_min,
    ROUND(MAX(spatial_score), 3)    AS spatial_max,
    ROUND(AVG(spatial_score), 3)    AS spatial_avg,
    ROUND(STDDEV(spatial_score), 3) AS spatial_stddev,

    ROUND(MIN(wind_score), 3)       AS wind_min,
    ROUND(MAX(wind_score), 3)       AS wind_max,
    ROUND(AVG(wind_score), 3)       AS wind_avg,
    ROUND(STDDEV(wind_score), 3)    AS wind_stddev,

    ROUND(MIN(wave_score), 3)       AS wave_min,
    ROUND(MAX(wave_score), 3)       AS wave_max,
    ROUND(AVG(wave_score), 3)       AS wave_avg,
    ROUND(STDDEV(wave_score), 3)    AS wave_stddev,

    ROUND(MIN(final_score), 3)      AS final_min,
    ROUND(MAX(final_score), 3)      AS final_max,
    ROUND(AVG(final_score), 3)      AS final_avg,
    ROUND(STDDEV(final_score), 3)   AS final_stddev

FROM `med-offshore-test.wind_intermediate.int_site_composite_score`;
```

**Expected:**
- No dimension stddev < 0.05 (scores are not differentiating)
- `final_score` range should be at least 0.2 wide
- If min = max for any dimension, that dimension is broken

### 3.2 — Score histogram (decile breakdown)

```sql
WITH binned AS (
    SELECT
        final_score,
        NTILE(10) OVER (ORDER BY final_score) AS decile
    FROM `med-offshore-test.wind_intermediate.int_site_composite_score`
)
SELECT
    decile,
    ROUND(MIN(final_score), 3) AS min_score,
    ROUND(MAX(final_score), 3) AS max_score,
    COUNT(*) AS site_count
FROM binned
GROUP BY 1
ORDER BY 1;
```

**Expected:** Roughly equal counts per decile. Heavy clustering at the top means scores are not differentiating well.

### 3.3 — Sites hitting score ceiling or floor

```sql
SELECT
    COUNTIF(wind_score = 1.0)    AS wind_at_ceiling,
    COUNTIF(spatial_score = 1.0) AS spatial_at_ceiling,
    COUNTIF(wave_score = 0.0)    AS wave_at_floor,
    COUNTIF(wind_score = 0.0)    AS wind_at_floor,
    COUNT(*) AS total_sites
FROM `med-offshore-test.wind_intermediate.int_site_composite_score`;
```

**Expected:** A few sites hitting ceiling/floor is fine. More than 20% hitting any ceiling or floor means the scoring curve threshold needs adjusting.

---

## 4. Wind/Wave Correlation Check

The Gulf of Lion is dominated by the Mistral — wind and wave conditions are correlated. If correlation is too high, the 20% wave weight is partially redundant with the 40% wind weight.

```sql
SELECT
    ROUND(CORR(wind_score, wave_score), 3)               AS wind_wave_score_corr,
    ROUND(CORR(avg_wind_speed_ms, avg_wave_height_m), 3) AS windspeed_waveheight_corr
FROM `med-offshore-test.wind_intermediate.int_site_composite_score`;
```

**Interpretation:**
- `< 0.4` — low correlation, weights are independent, no action needed
- `0.4–0.7` — moderate correlation, document and monitor
- `> 0.7` — high Mistral correlation, consider reducing wave weight or introducing a Mistral exposure index

---

## 5. Survivability Distribution

```sql
SELECT
    survivability_class,
    turbine_type,
    COUNT(*) AS site_count,
    ROUND(AVG(raw_final_score), 3)          AS avg_raw_score,
    ROUND(AVG(final_score), 3)              AS avg_final_score,
    ROUND(AVG(survivability_multiplier), 3) AS avg_multiplier
FROM `med-offshore-test.wind_intermediate.int_site_composite_score`
GROUP BY 1, 2
ORDER BY 1, 2;
```

**Expected:** Most sites should be `high` or `medium`. A large number of `low` survivability sites suggests extreme wave outliers worth investigating.

### 5.1 — Sites penalised by survivability multiplier

```sql
SELECT
    site_name,
    survivability_class,
    survivability_multiplier,
    ROUND(raw_final_score, 3)               AS raw_final_score,
    ROUND(final_score, 3)                   AS final_score,
    ROUND(raw_final_score - final_score, 3) AS score_lost_to_penalty
FROM `med-offshore-test.wind_intermediate.int_site_composite_score`
WHERE survivability_multiplier < 1.0
ORDER BY score_lost_to_penalty DESC;
```

**Expected:** Shows which sites are penalised and by how much. Review the highest `score_lost_to_penalty` sites — are they in genuinely rough areas?

---

## 6. Turbine Type Scoring Consistency

Verify fixed and floating turbines are scored by the correct curves.

```sql
SELECT
    turbine_type,
    COUNT(*) AS site_count,
    ROUND(AVG(depth_m), 1)              AS avg_depth_m,
    ROUND(AVG(distance_to_coast_km), 1) AS avg_dist_km,
    ROUND(AVG(spatial_score), 3)        AS avg_spatial_score,
    ROUND(AVG(depth_score), 3)          AS avg_depth_score,
    ROUND(AVG(coast_score), 3)          AS avg_coast_score
FROM `med-offshore-test.wind_intermediate.int_site_spatial_score`
WHERE turbine_type != 'not_viable'
GROUP BY 1
ORDER BY 1;
```

**Expected:**
- Fixed sites score higher on `depth_score` than floating (shallower = better for linear curve)
- Floating sites near 180m depth should score higher than floating sites at 50m or 900m
- Fixed turbines in viable mart: all `distance_to_coast_km` >= 11km
- Floating turbines in viable mart: all `distance_to_coast_km` >= 5km

---

## 7. Spot Checks — Top and Bottom Sites

### 7.1 — Top 10 sites

```sql
SELECT
    site_rank,
    site_name,
    center_lat,
    center_lon,
    turbine_type,
    depth_m,
    distance_to_coast_km,
    ROUND(spatial_score, 3)   AS spatial_score,
    ROUND(wind_score, 3)      AS wind_score,
    ROUND(wave_score, 3)      AS wave_score,
    survivability_class,
    survivability_multiplier,
    ROUND(raw_final_score, 3) AS raw_final_score,
    ROUND(final_score, 3)     AS final_score
FROM `med-offshore-test.wind_marts.mart_offshore_site_prioritization`
ORDER BY site_rank ASC
LIMIT 10;
```

**Manual check:** Plot these 10 sites on a map. They should all be visibly offshore in the Gulf of Lion in areas known for strong Mistral winds. If a top site looks geographically wrong, investigate its raw data.

### 7.2 — Bottom 10 sites

```sql
SELECT
    site_rank,
    site_name,
    center_lat,
    center_lon,
    turbine_type,
    depth_m,
    distance_to_coast_km,
    ROUND(spatial_score, 3)  AS spatial_score,
    ROUND(wind_score, 3)     AS wind_score,
    ROUND(wave_score, 3)     AS wave_score,
    survivability_class,
    ROUND(final_score, 3)    AS final_score
FROM `med-offshore-test.wind_marts.mart_offshore_site_prioritization`
ORDER BY site_rank DESC
LIMIT 10;
```

**Manual check:** Bottom sites should have an obvious reason for ranking low — very shallow, close to shore, low wind, or high waves.

---

## 8. Weight Sensitivity Analysis

Run this to check if small weight changes drastically reshuffle the top 10.

```sql
SELECT
    site_name,
    RANK() OVER (ORDER BY final_score DESC) AS current_rank_40_40_20,
    RANK() OVER (ORDER BY
        (0.35 * spatial_score) + (0.45 * wind_score) + (0.20 * wave_score) DESC
    ) AS alt_rank_35_45_20,
    RANK() OVER (ORDER BY
        (0.45 * spatial_score) + (0.35 * wind_score) + (0.20 * wave_score) DESC
    ) AS alt_rank_45_35_20,
    RANK() OVER (ORDER BY
        (0.33 * spatial_score) + (0.34 * wind_score) + (0.33 * wave_score) DESC
    ) AS alt_rank_equal,
    ROUND(final_score, 3) AS final_score
FROM `med-offshore-test.wind_intermediate.int_site_composite_score`
ORDER BY current_rank_40_40_20 ASC
LIMIT 20;
```

**Interpretation:** If the top 5 sites stay in the top 5 regardless of weight variation, results are robust. If the ranking shuffles dramatically, note this as a sensitivity risk in any report or presentation.

---

## 9. Gate Consistency Check

Verify no site in the decision mart violates the gate rules.

```sql
-- Should return 0 rows — any result here is a pipeline bug
SELECT
    site_name,
    turbine_type,
    depth_m,
    distance_to_coast_km
FROM `med-offshore-test.wind_intermediate.int_site_composite_score`
WHERE depth_m < 10
   OR depth_m > 1000
   OR (turbine_type = 'fixed'    AND distance_to_coast_km < 11)
   OR (turbine_type = 'floating' AND distance_to_coast_km < 5)
   OR turbine_type = 'not_viable';
```

**Expected:** Zero rows. Any result means a gate is not working correctly.

---

## 10. Documentation Consistency Checks

Manual — no SQL needed.

- [ ] YAML descriptions match SQL weights (currently 40/40/20)
- [ ] `int_site_composite_score` YAML mentions survivability multiplier
- [ ] `int_site_composite_score` YAML mentions turbine-type aware distance gates
- [ ] `mart_offshore_site_gis` YAML notes it is unfiltered and not for decision making
- [ ] `mart_offshore_site_prioritization` YAML notes it is the filtered decision layer
- [ ] All models have YAML entries with `unique` and `not_null` tests on primary keys
- [ ] No `accepted_values` tests missing the `arguments` property
- [ ] Run `dbt parse --show-all-deprecations` — should return clean

---

## 11. GIS Verification Checklist

To be completed in QGIS with a high-resolution land mask.

- [ ] Export `mart_offshore_site_gis` viable sites as CSV from BigQuery
- [ ] Load into QGIS — X = `center_lon`, Y = `center_lat`, CRS = EPSG:4326
- [ ] Load Natural Earth 1:10m land polygons: https://www.naturalearthdata.com/downloads/10m-physical-vectors/
- [ ] Run Vector → Research Tools → Select by Location (points intersecting land polygon)
- [ ] Export selected inland points as CSV
- [ ] Create `dbt/seeds/seed_excluded_sites.csv` from confirmed inland points
- [ ] Add seed filter to `mart_offshore_site_prioritization.sql`
- [ ] Run `dbt seed && dbt build`
- [ ] Re-verify top 10 sites are all visibly offshore

---

## Quick Reference — Pass/Fail Summary

| Check | Section | Pass condition |
|---|---|---|
| 102 sites in GIS mart | 1.1 | COUNT = 102 |
| 102 sites in unfiltered | 1.1 | COUNT = 102 |
| No negative depths | 2.2 | negative_depths = 0 |
| Coordinates in bounds | 2.1 | all sites within Gulf of Lion |
| Gate consistency | 9 | 0 rows returned |
| Score range adequate | 3.1 | final stddev > 0.05 |
| Wind/wave correlation | 4 | corr < 0.7 |
| Excluded sites have null rank | 1.4 | has_rank = 0 for excluded |
| Top 10 visually offshore | 7.1 | Manual GIS check |
| YAML matches SQL weights | 10 | Manual check |
| No deprecation warnings | 10 | dbt parse returns clean |
| GIS land mask clear | 11 | Manual QGIS check |