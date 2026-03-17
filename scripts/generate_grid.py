import yaml
import numpy as np
from google.cloud import bigquery
import json
import os

# ── Config ────────────────────────────────────────────────────────────────────


AREAS_FILE  = os.path.join(os.path.dirname(__file__), '..', 'areas.yaml')
PROJECT_ID  = os.environ["GCP_PROJECT_ID"]
DATASET     = "med_wind_prod"
TABLE       = "raw_bathymetry"
BQ_TABLE    = f"{PROJECT_ID}.{DATASET}.{TABLE}"
CREDENTIALS = "keys/google_credentials.json"

# ── Load areas.yaml ───────────────────────────────────────────────────────────

with open(AREAS_FILE) as f:
    config = yaml.safe_load(f)

active_areas = [a for a in config['areas'] if a['active']]
print(f"Active areas: {[a['name'] for a in active_areas]}\n")

# ── BigQuery client ───────────────────────────────────────────────────────────

client = bigquery.Client.from_service_account_json(CREDENTIALS, project=PROJECT_ID)

# ── Generate grid points per area ─────────────────────────────────────────────

all_points = []

for area in active_areas:
    name       = area['name']
    lat_min    = area['lat_min']
    lat_max    = area['lat_max']
    lon_min    = area['lon_min']
    lon_max    = area['lon_max']
    resolution = area['resolution']
    depth_max  = area['depth_max_m']   # e.g. -2000

    print(f"Processing area: {name}")

    # Generate candidate grid points
    lats = np.arange(lat_min, lat_max + resolution, resolution)
    lons = np.arange(lon_min, lon_max + resolution, resolution)
    print(f"  Candidate grid: {len(lats)} lats × {len(lons)} lons = {len(lats)*len(lons)} points")

    # Query BigQuery to keep only marine points within depth range
    query = f"""
        SELECT
            ROUND(latitude  / {resolution}) * {resolution} AS lat,
            ROUND(longitude / {resolution}) * {resolution} AS lon,
            AVG(elevation_m) AS avg_depth
        FROM `{BQ_TABLE}`
        WHERE latitude  BETWEEN {lat_min} AND {lat_max}
          AND longitude BETWEEN {lon_min} AND {lon_max}
          AND elevation_m BETWEEN {depth_max} AND 0
        GROUP BY 1, 2
        ORDER BY 1, 2
    """

    results = client.query(query).result()
    points  = [{"lat": row.lat, "lon": row.lon, "avg_depth": round(row.avg_depth, 1)} for row in results]
    print(f"  Marine points after depth filter: {len(points)}")

    # Build KV-style keys:  GULF_OF_LION_41.5_3.25
    for p in points:
        key = f"{name.upper()}_{p['lat']}_{p['lon']}"
        all_points.append({
            "key":       key,
            "lat":       p['lat'],
            "lon":       p['lon'],
            "avg_depth": p['avg_depth'],
            "area":      name
        })

# ── Output ────────────────────────────────────────────────────────────────────

print(f"\nTotal grid points: {len(all_points)}\n")

# Print KV store entries (paste these into site_key_values.yaml)
print("── KV Store entries (paste into site_key_values.yaml) ──")
for p in all_points:
    kv = json.dumps({"key": p['key'], "lat": p['lat'], "lon": p['lon']})
    print(f"  - '{kv}'")

# Also save to a JSON file for reference
output_path = os.path.join(os.path.dirname(__file__), '..', 'grid_points.json')
with open(output_path, 'w') as f:
    json.dump(all_points, f, indent=2)
print(f"\nFull grid saved to grid_points.json")