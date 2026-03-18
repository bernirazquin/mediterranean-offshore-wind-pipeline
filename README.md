# Gulf of Lion Offshore Wind Pipeline

An end-to-end batch data pipeline to identify optimal offshore wind turbine installation sites in the Gulf of Lion, using 19 years of historical wind, wave, bathymetric, and coastline data across 111 grid points at 0.25° resolution.


> Developed as part of the [Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp) capstone project.

---
## Problem Statement

Where in the Gulf of Lion should offshore wind turbines be installed?

The Gulf of Lion (northwestern Mediterranean) is one of Europe's most promising offshore wind zones — the [EFGL project](https://www.eoliennesenmer.fr/efgl) is currently installing the first commercial floating wind turbines there, with a 250MW follow-up (EFLO) awarded in December 2024.

This pipeline analyses 19 years of ERA5 wind and wave reanalysis data across a 0.25° grid to score and rank grid cells by suitability for offshore wind development, combining wind speed, sea depth, and distance to coast.

But suitability analysis is only part of the picture.

### Beyond Commercial Development

Offshore wind suitability analysis is not only a tool for energy developers — it is equally valuable for environmental planners, marine biologists, and policymakers.

The same pipeline that identifies the best turbine locations can be inverted to highlight the areas most likely to be targeted for development, enabling proactive environmental assessment before projects begin rather than reactive mitigation after approval.

Future iterations of this pipeline are designed to incorporate additional layers that would make it a genuine environmental planning tool:

- **Marine protected areas** (Natura 2000, IUCN categories) — identify overlap between high-suitability zones and protected habitats
- **Species migration corridors** — seabird flyways, cetacean feeding grounds, fish spawning areas
- **Benthic habitat maps** — seabed classification to assess impact on bottom-dwelling ecosystems
- **Shipping lanes and fishing grounds** — conflict mapping with existing maritime activities

The architecture is deliberately extensible: adding a new spatial layer requires only a new Python ingestion script and a new dbt staging model. The suitability scoring in `fct_site_suitability` can then incorporate environmental constraints as penalty weights, producing scores that balance energy yield against ecological impact.

The goal is a pipeline that answers not just *"where should we build?"* but *"where can we build responsibly?"*

---

## Design Decisions

### Spatial resolution
Early versions used single representative coordinates per Mediterranean basin. This was replaced with a 0.25° grid over the Gulf of Lion to enable meaningful spatial analysis — single points cannot capture variance in wind speed, depth, or distance to coast across large areas.

The Gulf of Lion was selected as the focus area due to active offshore wind development and well-documented favourable conditions validated by existing literature (min LCOE ~95 €/MWh, Plan-bleu).

---

## Architecture

```
Open-Meteo API  ──┐
ETOPO 2022      ──┼──► Kestra / Python scripts ──► GCS (Data Lake) ──► BigQuery ──► dbt ──► *to be set*
Natural Earth   ──┘
```

**Kestra flows:**
- `site_key_values` → seeds 111 Gulf of Lion grid coordinates into KV store
- `wind_data_ingestion` → fetches ERA5 wind data, uploads to GCS, loads to BigQuery
- `wave_data_ingestion` → fetches Marine ERA5-Ocean wave data, uploads to GCS, loads to BigQuery
- `site_data_ingestion` → runs wind + wave in parallel
- `site_data_backfill` → historical loop (111 grid points × 19 years, 2006–2024)

**Python scripts (static reference data):**
- `scripts/generate_grid.py` → reads `areas.yaml`, queries BigQuery bathymetry, outputs marine grid points
- `scripts/load_bathymetry.py` → downloads ETOPO 2022 via OPeNDAP, uploads to GCS tile by tile, loads to BigQuery
- `scripts/load_coastline_distance.py` → downloads Natural Earth 1:10m coastline, computes distance transform, uploads to GCS, loads to BigQuery

**Config:**
- `areas.yaml` → defines the focus area bounding box and resolution. Add a new area here and re-run `generate_grid.py` to extend the pipeline to any new region.

**BigQuery tables:**
- `med_wind_prod.raw_wind_data` — partitioned by month, clustered by site (~18.5M rows)
- `med_wind_prod.raw_wave_data` — partitioned by month, clustered by site (~18.5M rows)
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
| Transformations | dbt |
| Dashboard | ***to be set*** |
| Static ingestion | Python + xarray + geopandas + scipy |
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

### 4. Generate grid points
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export GCP_PROJECT_ID=your-project-id
python scripts/generate_grid.py
```

### 5. Run Kestra flows in order

| Step | Flow | Action |
|------|------|--------|
| 1 | `site_key_values` | Run once — seeds 111 grid coordinates |
| 2 | `wind_data_ingestion` | Test: GULF_OF_LION_43.0_4.0, 2023-01-01 → 2023-01-31 |
| 3 | `wave_data_ingestion` | Test: GULF_OF_LION_43.0_4.0, 2023-01-01 → 2023-01-31 |
| 4 | `site_data_backfill` | Run once — ~2–4 hours (111 sites × 19 years) |

### 6. Load static reference data
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python scripts/load_bathymetry.py          # ~20 min
python scripts/load_coastline_distance.py  # ~10 min
```

> Both scripts upload to GCS first, then load to BigQuery from GCS. Safe to re-run.

---

### 7. Run dbt transformations
```bash
cd dbt && dbt run
```
---

## Known Limitations

- Wave data uses ERA5-Ocean model which has coarser resolution than wind data
- `raw_coastline_distance` contains land cells — filtered in dbt staging
- Distance calculation uses mean latitude (~42°N) for WGS84 correction — ~2% error at bounding box edges
- Wind/wave data are point measurements snapped to Open-Meteo's internal grid

---

## Roadmap
- [ ] Daily schedule for forward updates
- [ ] Additional area support via `areas.yaml` (Bay of Biscay, Aegean)
- [ ] Additional variables: `wind_speed_80m`, `wind_gusts_10m`, `swell_wave_height`
- [ ] Additional static layers: Natura 2000 protected areas, shipping lanes