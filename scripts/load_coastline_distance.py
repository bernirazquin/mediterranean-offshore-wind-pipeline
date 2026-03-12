"""
load_coastline_distance.py
Computes distance to coast for Mediterranean marine cells using
Natural Earth 1:10m coastline and scipy distance transform.

All sources use WGS84 (EPSG:4326) — no reprojection needed.
Distance calculation accounts for longitude compression at ~38N.
Uploads in lat strips to avoid OOM on low-RAM environments.

Run from project root: python scripts/load_coastline_distance.py
"""

import io, requests
import numpy as np
import pandas as pd
import geopandas as gpd
from scipy.ndimage import distance_transform_edt
from google.cloud import bigquery, storage

LAT_MIN, LAT_MAX = 30.0, 46.0
LON_MIN, LON_MAX = -6.0, 37.0
RESOLUTION       = 15 / 3600
STRIP_SIZE       = 200
PROJECT_ID       = "med-offshore-wind-489212"
GCS_BUCKET       = "med_wind_data_lake_med-offshore-wind-489212"
TABLE_ID         = f"{PROJECT_ID}.med_wind_prod.raw_coastline_distance"
CREDENTIALS      = "keys/google_credentials.json"
GCS_PREFIX       = "raw/coastline_distance"
GCS_URI          = f"gs://{GCS_BUCKET}/{GCS_PREFIX}/strip_*.parquet"
NE_URL           = "https://naciscdn.org/naturalearth/10m/physical/ne_10m_coastline.zip"

LAT_MEAN     = (LAT_MIN + LAT_MAX) / 2
KM_PER_LAT   = RESOLUTION * 111.0
KM_PER_LON   = RESOLUTION * 111.0 * np.cos(np.radians(LAT_MEAN))
KM_PER_PIXEL = (KM_PER_LAT + KM_PER_LON) / 2


def main():
    gcs = storage.Client.from_service_account_json(CREDENTIALS)
    bq  = bigquery.Client.from_service_account_json(CREDENTIALS)

    # Download and clip coastline
    print("Downloading Natural Earth 1:10m coastline...")
    r = requests.get(NE_URL, timeout=60)
    r.raise_for_status()
    gdf = gpd.read_file(io.BytesIO(r.content)).cx[LON_MIN:LON_MAX, LAT_MIN:LAT_MAX]
    print(f"  {len(gdf)} coastline segments clipped to Mediterranean")

    # Rasterize onto ETOPO grid
    lats   = np.arange(LAT_MIN, LAT_MAX, RESOLUTION)
    lons   = np.arange(LON_MIN, LON_MAX, RESOLUTION)
    raster = np.zeros((len(lats), len(lons)), dtype=np.uint8)

    for geom in gdf.geometry:
        if geom is None:
            continue
        coords = list(geom.coords) if geom.geom_type == "LineString" \
            else [pt for line in geom.geoms for pt in line.coords]
        for lon, lat in coords:
            row = int((lat - LAT_MIN) / RESOLUTION)
            col = int((lon - LON_MIN) / RESOLUTION)
            if 0 <= row < len(lats) and 0 <= col < len(lons):
                raster[row, col] = 1

    print(f"  {raster.sum():,} coastline cells rasterized")

    # Full distance transform — must run on complete raster for correct results
    print("  Computing distance transform...")
    dist_km = distance_transform_edt(raster == 0) * KM_PER_PIXEL
    del raster, gdf

    # Upload in lat strips to GCS to avoid building 17M row DataFrame at once
    print("Uploading strips to GCS...")
    total_rows = 0

    for i in range(0, len(lats), STRIP_SIZE):
        lat_strip  = lats[i:i + STRIP_SIZE]
        dist_strip = dist_km[i:i + STRIP_SIZE, :]
        lon_grid, lat_grid = np.meshgrid(lons, lat_strip)

        df = pd.DataFrame({
            "latitude":             lat_grid.ravel(),
            "longitude":            lon_grid.ravel(),
            "distance_to_coast_km": dist_strip.ravel(),
        })
        df = df[df["distance_to_coast_km"] > 0]
        total_rows += len(df)

        buf = io.BytesIO()
        df.to_parquet(buf, index=False)
        buf.seek(0)
        gcs.bucket(GCS_BUCKET).blob(
            f"{GCS_PREFIX}/strip_{i:05d}.parquet"
        ).upload_from_file(buf)
        del df, buf

    print(f"  {total_rows:,} marine cells uploaded")

    # Load all strips from GCS to BigQuery using wildcard URI
    print(f"Loading to BigQuery: {TABLE_ID}")
    bq.load_table_from_uri(
        GCS_URI, TABLE_ID,
        job_config=bigquery.LoadJobConfig(
            write_disposition="WRITE_TRUNCATE",
            source_format=bigquery.SourceFormat.PARQUET,
        )
    ).result()
    print(f"Done. {total_rows:,} rows loaded to {TABLE_ID}")


if __name__ == "__main__":
    main()