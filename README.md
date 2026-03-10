# Mediterranean Offshore Wind Pipeline

An end-to-end batch data pipeline to identify the best offshore wind turbine installation sites in the Mediterranean basin, using 20 years of historical wind and wave data.

> Developed as part of the [Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp) capstone project.

---

## Architecture

```
Open-Meteo API → Kestra → GCS (Data Lake) → BigQuery → dbt → *to be set*
```

**Kestra flows:**
- `site_key_values` → seeds coordinates into KV store
- `wind_data_ingestion` → fetches ERA5 wind data, loads to BigQuery
- `wave_data_ingestion` → fetches Marine wave data, loads to BigQuery
- `site_data_ingestion` → runs wind + wave in parallel
- `site_data_backfill` → historical loop (14 sites × 19 years)

**BigQuery tables** — both partitioned by month, clustered by site:
- `med_wind_prod.raw_wind_data`
- `med_wind_prod.raw_wave_data`

---

## Tech Stack

| Layer | Tool |
|-------|------|
| Orchestration | Kestra v1.1 |
| Data Lake | Google Cloud Storage |
| Data Warehouse | Google BigQuery |
| Transformations | dbt (coming soon) |
| Dashboard | (coming soon) |
| Infrastructure | Docker + Terraform |

---

## How to Reproduce

### Prerequisites
- Docker & Docker Compose
- Terraform v1.5+
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

### 4. Run flows in order

| Step | Flow | Action |
|------|------|--------|
| 1 | `site_key_values` | Run once |
| 2 | `wind_data_ingestion` | Test: GULF_OF_LYON, 2020 |
| 3 | `wave_data_ingestion` | Test: GULF_OF_LYON, 2020 |
| 4 | `site_data_ingestion` | Test: GULF_OF_LYON, 2020 |
| 5 | `site_data_backfill` | Run once — ~2-4 hours |

---

## Roadmap
- [ ] dbt suitability scoring models
- [ ] Dashboard
- [ ] Daily schedule for forward updates