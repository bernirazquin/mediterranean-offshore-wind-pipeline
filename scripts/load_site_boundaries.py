import json
import os
import pandas as pd
from shapely.geometry import shape
from google.cloud import storage, bigquery

# --- Configuration ---
PROJECT_ID  = "med-offshore-wind-489212"
GCS_BUCKET  = "med_wind_data_lake_med-offshore-wind-489212"
DATASET     = "med_wind_prod"
TABLE       = "raw_site_boundaries"
TABLE_ID    = f"{PROJECT_ID}.{DATASET}.{TABLE}"
CREDENTIALS = "keys/google_credentials.json"
GCS_PATH    = "raw/site_boundaries/site_boundaries.parquet"
SOURCE_FILE = "data/med_sea_boundaries.geojson"

# --- Site to IHO polygon mapping ---
# Each of the 14 sites is assigned to its containing IHO sea area polygon.
# Balearic Sea was merged into Western Basin to avoid cutting coastal sites.
# Gulf of Lion and Costa Brava fall inside Western Basin.
# Strait of Sicily falls inside Ionian Sea polygon.
# Libyan Coast, Levantine Sea and Cyprus Coast fall inside Eastern Basin.
SITE_POLYGON_MAPPING = {
    "ALBORAN_SEA":        "Alboran Sea",
    "GULF_OF_VALENCIA":   "Mediterranean Sea - Western Basin",
    "EBRO_DELTA":         "Mediterranean Sea - Western Basin",
    "COSTA_BRAVA":        "Mediterranean Sea - Western Basin",
    "GULF_OF_LYON":       "Mediterranean Sea - Western Basin",
    "BALEARIC_SEA":       "Mediterranean Sea - Western Basin",
    "TYRRHENIAN_SEA":     "Tyrrhenian Sea",
    "STRAIT_OF_SICILY":   "Ionian Sea",
    "NORTH_ADRIATIC_SEA": "Adriatic Sea",
    "IONIAN_SEA":         "Ionian Sea",
    "AEGEAN_SEA":         "Aegean Sea",
    "LIBYAN_COAST":       "Mediterranean Sea - Eastern Basin",
    "LEVANTINE_SEA":      "Mediterranean Sea - Eastern Basin",
    "CYPRUS_COAST":       "Mediterranean Sea - Eastern Basin",
}

def main():
    # --- Read GeoJSON ---
    print("Reading GeoJSON...")
    with open(SOURCE_FILE) as f:
        geojson = json.load(f)

    # --- Build polygon lookup by NAME ---
    # Convert each MultiPolygon geometry to WKT for BigQuery ST_GEOGFROMTEXT()
    polygon_wkt = {}
    for feature in geojson["features"]:
        name = feature["properties"]["NAME"]
        geom = shape(feature["geometry"])
        polygon_wkt[name] = geom.wkt

    # --- Build site boundaries dataframe ---
    # One row per site with its containing polygon WKT
    rows = []
    for site, polygon_name in SITE_POLYGON_MAPPING.items():
        rows.append({
            "site_name":    site,
            "polygon_name": polygon_name,
            "geometry_wkt": polygon_wkt[polygon_name],
        })

    df = pd.DataFrame(rows)
    print(f"Built {len(df)} site boundary rows")
    print(df[["site_name", "polygon_name"]].to_string())

    # --- Upload to GCS ---
    print(f"\nUploading to GCS: gs://{GCS_BUCKET}/{GCS_PATH}")
    gcs_client = storage.Client.from_service_account_json(CREDENTIALS)
    buffer = __import__('io').BytesIO()
    df.to_parquet(buffer, index=False)
    buffer.seek(0)
    gcs_client.bucket(GCS_BUCKET).blob(GCS_PATH).upload_from_file(
        buffer, content_type="application/octet-stream"
    )
    print("Upload complete")

    # --- Load to BigQuery ---
    print(f"\nLoading to BigQuery: {TABLE_ID}")
    bq_client = bigquery.Client.from_service_account_json(CREDENTIALS)
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.PARQUET,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    job = bq_client.load_table_from_uri(
        f"gs://{GCS_BUCKET}/{GCS_PATH}",
        TABLE_ID,
        job_config=job_config
    )
    job.result()
    print(f"Done. {bq_client.get_table(TABLE_ID).num_rows} rows loaded to {TABLE_ID}")

if __name__ == "__main__":
    main()