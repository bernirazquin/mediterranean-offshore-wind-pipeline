# Mediterranean Offshore Wind Pipeline

An end-to-end batch data pipeline to identify the best offshore wind turbine installation sites in the Mediterranean basin, using 19 years of historical wind, wave, bathymetric, and coastline data.

> Developed as part of the [Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp) capstone project.

---

## Architecture

```
Open-Meteo API  ──┐
ETOPO 2022      ──┼──► Kestra / Python scripts ──► GCS (Data Lake) ──► BigQuery ──► dbt ──► *to be set*
Natural Earth   ──┘
```

**Kestra flows:**
- `site_key_values` → seeds coordinates into KV store
- `wind_data_ingestion` → fetches ERA5 wind data, uploads to GCS, loads to BigQuery
- `wave_data_ingestion` → fetches Marine ERA5-Ocean wave data, uploads to GCS, loads to BigQuery
- `site_data_ingestion` → runs wind + wave in parallel
- `site_data_backfill` → historical loop (14 sites × 19 years)

**Python scripts (static reference data):**
- `scripts/load_bathymetry.py` → downloads ETOPO 2022 via OPeNDAP, uploads to GCS tile by tile, loads to BigQuery
- `scripts/load_coastline_distance.py` → downloads Natural Earth 1:10m coastline, computes distance transform, uploads to GCS, loads to BigQuery

**BigQuery tables:**
- `med_wind_prod.raw_wind_data` — partitioned by month, clustered by site
- `med_wind_prod.raw_wave_data` — partitioned by month, clustered by site
- `med_wind_prod.raw_bathymetry` — ~17M marine cells, WGS84
- `med_wind_prod.raw_coastline_distance` — ~17M cells, land cells filtered in dbt

**GCS structure:**
```
raw/
  wind/{SITE}/{start_date}_{end_date}.ndjson
  wave/{SITE}/{start_date}_{end_date}.ndjson
  bathymetry/tile_00.parquet ... tile_03.parquet
  coastline_distance/strip_*.parquet
```

---

## Tech Stack

| Layer | Tool |
|-------|------|
| Orchestration | Kestra v1.1 |
| Data Lake | Google Cloud Storage |
| Data Warehouse | Google BigQuery |
| Static ingestion | Python + xarray + geopandas + scipy |
| Transformations | dbt (in progress) |
| Dashboard | (in progress) |
| Infrastructure | Docker + Terraform |

---

## How to Reproduce

### Prerequisites
- Docker & Docker Compose
- Terraform v1.5+
- Python 3.11+ with venv
- GCP project with a service account (`Storage Object Admin`, `BigQuery Data Editor`, `BigQuery Job User`)

### 1. Clone and configure
```bash
git clone https://github.com/bernirazquin/mediterranean-offshore-wind-pipeline.git
cd mediterranean-offshore-wind-pipeline
cp .env.example .env
```

Fill in `.env`:
```bash
GCP_PROJECT_ID=your-project-id
GCP_SERVICE_ACCOUNT_B64=$(base64 -i keys/google_credentials.json | tr -d '\n')
GCS_BUCKET=your-bucket-name
GEMINI_API_KEY=your-key        # optional
```

### 2. Provision infrastructure
```bash
cd terraform && terraform init && terraform apply && cd ..
```

### 3. Start services
```bash
docker compose up -d
```

Kestra UI → http://localhost:8080 (`admin@wind.com` / `Admin1234!`)

### 4. Run Kestra flows in order

| Step | Flow | Action |
|------|------|--------|
| 1 | `site_key_values` | Run once |
| 2 | `wind_data_ingestion` | Test: GULF_OF_LYON, 2020 |
| 3 | `wave_data_ingestion` | Test: GULF_OF_LYON, 2020 |
| 4 | `site_data_ingestion` | Test: GULF_OF_LYON, 2020 |
| 5 | `site_data_backfill` | Run once — ~2–4 hours |

### 5. Load static reference data
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python scripts/load_bathymetry.py          # ~20 min
python scripts/load_coastline_distance.py  # ~10 min
```

> Both scripts upload to GCS first, then load to BigQuery from GCS. Safe to re-run.

---

## Known Limitations

- `raw_coastline_distance` contains land cells — filtered in dbt staging via join with `raw_bathymetry`
- Distance calculation uses mean latitude (~38°N) for WGS84 correction — ~3% error at bounding box edges
- Wind/wave data are point measurements, not areal averages

---

## Roadmap
- [ ] dbt suitability scoring models
- [ ] Dashboard
- [ ] Daily schedule for forward updates
- [ ] Additional variables: `wind_speed_80m`, `wind_gusts_10m`, `swell_wave_height`
- [ ] Additional static layers: Natura 2000 protected areas, shipping lanes