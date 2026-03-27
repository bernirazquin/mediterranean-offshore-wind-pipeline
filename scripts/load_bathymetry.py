"""
load_bathymetry.py
------------------
Downloads bathymetric data for the Mediterranean Sea from ETOPO 2022 (NOAA)
via OPeNDAP, uploads each tile to GCS as parquet (data lake), then loads
to BigQuery from GCS.

Follows the same pattern as the Kestra wind/wave ingestion flows:
    ETOPO API → GCS raw/bathymetry/ → BigQuery raw_bathymetry

Each tile is processed and uploaded independently to avoid OOM errors.
Peak RAM usage is ~350MB regardless of total dataset size.

Usage (always run from project root):
    python scripts/load_bathymetry.py

Requirements:
    - keys/google_credentials.json must exist
    - .venv with xarray, netCDF4, pandas, google-cloud-bigquery,
      google-cloud-storage, pyarrow installed
"""

import io
import os
import xarray as xr
import pandas as pd
import sys
from google.cloud import bigquery, storage

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Mediterranean Sea bounding box
LAT_MIN, LAT_MAX =  30.0, 46.0
LON_MIN, LON_MAX =  -6.0, 37.0

# GCP
PROJECT_ID  = os.getenv("GCP_PROJECT_ID")
GCS_BUCKET  = os.getenv("GCS_BUCKET")
DATASET     = "med_wind_prod"
TABLE       = "raw_bathymetry"
TABLE_ID    = f"{PROJECT_ID}.{DATASET}.{TABLE}"
CREDENTIALS = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "keys/google_credentials.json")


# ETOPO 2022 tiles via OPeNDAP (NOAA THREDDS server).
# Each tile covers a 15° x 15° area. The prefix (e.g. N45E000) indicates
# the top-left corner: N45 = lat 30-45N, E000 = lon 0-15E.
# Together these four tiles cover the full Mediterranean bounding box.

# Test mode — only download tile covering Gulf of Lion
TEST_MODE = "--test" in sys.argv
TILES = [
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N45W015_surface.nc",
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N45E000_surface.nc",
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N45E015_surface.nc",
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N45E030_surface.nc",
] if not TEST_MODE else [
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N45E000_surface.nc",
]

# Number of latitude rows processed at a time during raster download.
# 500 rows keeps peak RAM well under 1GB during the download phase.
CHUNK_SIZE = 500

# BigQuery schema — shared across upload and load steps
BQ_SCHEMA = [
    bigquery.SchemaField("latitude",    "FLOAT64"),
    bigquery.SchemaField("longitude",   "FLOAT64"),
    bigquery.SchemaField("elevation_m", "FLOAT64"),
]

# ---------------------------------------------------------------------------
# Processing
# ---------------------------------------------------------------------------

def process_tile(url: str) -> pd.DataFrame:
    """
    Opens a single ETOPO tile via OPeNDAP, clips it to the Mediterranean
    bounding box, and returns a DataFrame of marine cells only (elevation < 0).
    Processes the tile in latitude chunks to avoid memory exhaustion.
    """
    tile_name = url.split("/")[-1]
    print(f"  Fetching tile: {tile_name}")

    ds = xr.open_dataset(url)

    # Clip to Mediterranean bounding box
    ds_med = ds.sel(
        lat=slice(LAT_MIN, LAT_MAX),
        lon=slice(LON_MIN, LON_MAX)
    )

    chunks = []
    lat_values = ds_med.lat.values

    for i in range(0, len(lat_values), CHUNK_SIZE):
        lat_chunk = lat_values[i:i + CHUNK_SIZE]
        chunk_ds  = ds_med.sel(lat=lat_chunk)

        df_chunk = (
            chunk_ds["z"]
            .to_dataframe()
            .reset_index()[["lat", "lon", "z"]]
        )

        # Keep only marine cells (negative elevation = below sea level)
        df_chunk = df_chunk[df_chunk["z"] < 0]
        chunks.append(df_chunk)

    ds.close()

    df_tile = pd.concat(chunks, ignore_index=True)
    df_tile.columns = ["latitude", "longitude", "elevation_m"]
    print(f"    {len(df_tile):,} marine cells found")
    return df_tile


# ---------------------------------------------------------------------------
# GCS upload
# ---------------------------------------------------------------------------

def upload_tile_to_gcs(
    df: pd.DataFrame,
    gcs_client: storage.Client,
    tile_index: int
) -> str:
    """
    Uploads a tile DataFrame to GCS as parquet.
    Returns the GCS URI of the uploaded file.
    """
    gcs_path = f"raw/bathymetry/tile_{tile_index:02d}.parquet"
    gcs_uri  = f"gs://{GCS_BUCKET}/{gcs_path}"

    # Serialize to parquet in memory — no local file needed
    buffer = io.BytesIO()
    df.to_parquet(buffer, index=False)
    buffer.seek(0)

    bucket = gcs_client.bucket(GCS_BUCKET)
    blob   = bucket.blob(gcs_path)
    blob.upload_from_file(buffer, content_type="application/octet-stream")

    print(f"    Uploaded to GCS: {gcs_uri}")
    return gcs_uri


# ---------------------------------------------------------------------------
# BigQuery load
# ---------------------------------------------------------------------------

def load_tile_to_bigquery(
    gcs_uri: str,
    bq_client: bigquery.Client,
    write_disposition: str
) -> None:
    """
    Loads a single tile from GCS into BigQuery.
    write_disposition should be WRITE_TRUNCATE for the first tile
    and WRITE_APPEND for all subsequent tiles.
    """
    job_config = bigquery.LoadJobConfig(
        write_disposition=write_disposition,
        source_format=bigquery.SourceFormat.PARQUET,
        schema=BQ_SCHEMA,
    )

    job = bq_client.load_table_from_uri(gcs_uri, TABLE_ID, job_config=job_config)
    job.result()
    print(f"    Loaded to BigQuery ({write_disposition})")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("Downloading Mediterranean bathymetry from ETOPO 2022 (NOAA)...")
    print(f"Bounding box: lat {LAT_MIN}-{LAT_MAX}, lon {LON_MIN}-{LON_MAX}\n")

    gcs_client = storage.Client.from_service_account_json(CREDENTIALS)
    bq_client  = bigquery.Client.from_service_account_json(CREDENTIALS)

    total_rows = 0

    for i, url in enumerate(TILES):
        # Step 1 — download and process tile
        df_tile = process_tile(url)
        tile_rows = len(df_tile)

        # Step 2 — upload to GCS (data lake)
        gcs_uri = upload_tile_to_gcs(df_tile, gcs_client, i)

        # Free tile memory before BigQuery load
        del df_tile

        # Step 3 — load from GCS to BigQuery
        # First tile truncates the table, subsequent tiles append
        write_disposition = "WRITE_TRUNCATE" if i == 0 else "WRITE_APPEND"
        load_tile_to_bigquery(gcs_uri, bq_client, write_disposition)

        total_rows += tile_rows
        print(f"  Tile {i+1}/{len(TILES)} complete — {total_rows:,} rows loaded so far\n")

    print(f"Done. {total_rows:,} total rows loaded to {TABLE_ID}")
    print(f"GCS path: gs://{GCS_BUCKET}/raw/bathymetry/")


if __name__ == "__main__":
    main()