# ============================================================
# Gulf of Lion — Offshore Wind Pipeline
# ============================================================
# Usage:
#   make setup          → create venv and install dependencies
#   make infra          → provision GCP infrastructure via Terraform
#   make services       → start Kestra + dependencies via Docker Compose
#   make wait           → wait for Kestra to be healthy
#   make ingest         → load static reference data (bathymetry + coastline)
#   make flow-sync      → sync flow YAML files from repo to Kestra
#   make flow-keys      → seed 111 grid coordinates into Kestra KV store
#                         (111 raw points — 9 inland excluded later in dbt)
#   make flow-test      → test ingestion for one site (validates pipeline)
#   make flow-backfill  → full historical ingestion (~2-4 hours)
#   make flows          → flow-keys + flow-backfill together
#   make dbt            → run all dbt models and tests
#   make all            → full pipeline from scratch
#   make down           → stop all services
#   make clean          → remove venv and dbt target
# ============================================================

# Load .env file if it exists
ifneq (,$(wildcard .env))
    include .env
    export
endif

KESTRA_URL       = http://localhost:8080
KESTRA_NAMESPACE = company.wind
KESTRA_USER      = admin@wind.com
KESTRA_PASSWORD  = Admin1234!
KESTRA_AUTH      = $(KESTRA_USER):$(KESTRA_PASSWORD)

VENV             = .venv
PYTHON           = $(VENV)/bin/python
PIP              = $(VENV)/bin/pip

.DEFAULT_GOAL := help

.PHONY: all setup infra services wait ingest flows \
        flow-sync flow-keys flow-backfill flow-test dbt down clean help

# ── Help ─────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Gulf of Lion — Offshore Wind Pipeline"
	@echo "======================================"
	@echo "  make setup          create venv and install dependencies"
	@echo "  make infra          provision GCP infrastructure via Terraform"
	@echo "  make services       start Kestra + dependencies via Docker Compose"
	@echo "  make wait           wait for Kestra to be healthy"
	@echo "  make ingest         load bathymetry + coastline (~30 min)"
	@echo "  make flow-sync      sync flow YAML files from repo to Kestra"
	@echo "  make flow-keys      seed 111 grid coordinates into Kestra KV store"
	@echo "  make flow-test      test ingestion for one site (run before backfill)"
	@echo "  make flow-backfill  full historical ingestion (~2-4 hours)"
	@echo "  make flows          flow-keys + flow-backfill together"
	@echo "  make dbt            run all dbt models and tests"
	@echo "  make all            full pipeline from scratch"
	@echo "  make down           stop all services"
	@echo "  make clean          remove venv and dbt target"
	@echo ""

# ── Full pipeline ────────────────────────────────────────────
all: setup infra services wait ingest flow-sync flows dbt
	@echo "Pipeline complete."

# ── Python environment ───────────────────────────────────────
setup:
	@echo "Setting up Python environment..."
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt
	@echo "Done."

# ── Infrastructure ───────────────────────────────────────────
infra:
	@echo "Checking for GCP credentials..."
	@test -f keys/google_credentials.json || \
		(echo "ERROR: keys/google_credentials.json not found." && \
		echo "  See README.md for setup instructions." && \
		exit 1)
	@echo "Provisioning infrastructure..."
	@which terraform > /dev/null 2>&1 || (echo "Terraform not found. Installing..." && \
		wget -q https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip -O /tmp/terraform.zip && \
		unzip -q /tmp/terraform.zip -d /tmp/terraform-bin && \
		sudo mv /tmp/terraform-bin/terraform /usr/local/bin/ && \
		rm -rf /tmp/terraform.zip /tmp/terraform-bin && \
		echo "Terraform installed.")
	cd terraform && terraform init && terraform apply -auto-approve \
		-var="project=$(GCP_PROJECT_ID)" \
		-var="gcs_bucket_name=med_wind_data_lake_$(GCP_PROJECT_ID)" \
		-var="credentials=../keys/google_credentials.json"
	@echo "Done."

# ── Services ─────────────────────────────────────────────────
services:
	@echo "Starting Docker Compose services..."
	docker compose up -d
	@echo "Services started. Kestra UI → $(KESTRA_URL)"

down:
	@echo "Stopping services..."
	docker compose down

# ── Wait for Kestra to be ready ──────────────────────────────
wait:
	@echo "Waiting for Kestra to be ready..."
	@until curl -s -u "$(KESTRA_AUTH)" \
		"$(KESTRA_URL)/api/v1/flows/search" > /dev/null 2>&1; do \
		echo "  Kestra not ready yet, retrying in 5s..."; \
		sleep 5; \
	done
	@echo "Kestra is ready."

# ── Static reference data ────────────────────────────────────
ingest:
	@echo "Loading bathymetry data (~20 min)..."
	$(PYTHON) scripts/load_bathymetry.py
	@echo "Loading coastline distance data (~10 min)..."
	$(PYTHON) scripts/load_coastline_distance.py
	@echo "Static data loaded."

# ── Sync flows from repo to Kestra ───────────────────────────
flow-sync:
	@echo "Syncing flows to Kestra..."
	@for flow in flows/*.yaml; do \
		echo "  Updating $$flow..."; \
		curl -s -u "$(KESTRA_AUTH)" -X PUT \
			"$(KESTRA_URL)/api/v1/flows" \
			-H "Content-Type: application/x-yaml" \
			--data-binary "@$$flow"; \
		echo ""; \
	done
	@echo "Flows synced."

# ── Kestra flows ─────────────────────────────────────────────
flows: flow-keys flow-backfill
	@echo "All Kestra flows triggered."

flow-keys:
	@echo "Seeding 111 grid coordinates into Kestra KV store..."
	@echo "Note: 9 of 111 points are inland and will be excluded in dbt."
	@curl -s -u "$(KESTRA_AUTH)" -X POST \
		"$(KESTRA_URL)/api/v1/executions/$(KESTRA_NAMESPACE)/site_key_values" \
		-H "Content-Type: application/json" \
		-d '{}' | python3 -c \
		"import sys,json; r=json.load(sys.stdin); \
		print('  Execution ID:', r.get('id','unknown'))"
	@echo "Waiting 60s for key values to populate..."
	@sleep 60

flow-test: flow-keys
	@echo "Triggering site_data_ingestion for one site (test)..."
	@curl -s -u "$(KESTRA_AUTH)" -X POST \
		"$(KESTRA_URL)/api/v1/executions/$(KESTRA_NAMESPACE)/site_data_ingestion" \
		-H "Content-Type: multipart/form-data" \
		-F "site=GULF_OF_LION_43.0_4.0" \
		-F "start_date=2023-01-01" \
		-F "end_date=2023-01-31" | python3 -c \
		"import sys,json; r=json.load(sys.stdin); \
		print('  Execution ID:', r.get('id','unknown'))"
	@echo "Test ingestion triggered. Check Kestra UI at $(KESTRA_URL)"

flow-backfill:
	@echo "Triggering site_data_backfill (~2-4 hours)..."
	@echo "This ingests wind + wave data for all 111 sites × 19 years."
	@curl -s -u "$(KESTRA_AUTH)" -X POST \
		"$(KESTRA_URL)/api/v1/executions/$(KESTRA_NAMESPACE)/site_data_backfill" \
		-H "Content-Type: application/json" \
		-d '{}' | python3 -c \
		"import sys,json; r=json.load(sys.stdin); \
		print('  Execution ID:', r.get('id','unknown'))"
	@echo "Backfill triggered. Monitor at $(KESTRA_URL)"
	@echo "Run 'make dbt' after the backfill completes."

# ── dbt ──────────────────────────────────────────────────────
dbt:
	@echo "Running dbt pipeline..."
	cd dbt && \
		dbt deps && \
		dbt seed && \
		dbt build --full-refresh
	@echo "dbt complete. Expected: 121/121 nodes passing."

# ── Cleanup ──────────────────────────────────────────────────
clean:
	@echo "Cleaning up..."
	rm -rf $(VENV)
	rm -rf dbt/target
	rm -rf dbt/dbt_packages
	@echo "Done."


# ============================================================
# STEP BY STEP GUIDE FOR NEW CONTRIBUTORS
# ============================================================
#
# FIRST TIME SETUP (run once):
# ─────────────────────────────
# Step 1 — fill in your credentials
#   cp .env.example .env
#   (edit .env with your GCP project ID, service account, bucket name)
#   Place your GCP service account JSON key at keys/google_credentials.json
#
# Step 2 — set up Python environment
#   make setup
#
# Step 3 — provision GCP infrastructure
#   make infra
#   (installs Terraform if needed, creates GCS bucket and BigQuery datasets)
#   (uses GCP_PROJECT_ID from .env automatically)
#
# Step 4 — start Kestra
#   make services
#   make wait
#   (Kestra UI available at http://localhost:8080)
#   (login: admin@wind.com / Admin1234!)
#
# Step 5 — sync flows from repo to Kestra
#   make flow-sync
#   (pushes all YAML flow definitions from flows/ into Kestra)
#   (run this any time you update a flow file)
#
# Step 6 — load static reference data
#   make ingest
#   (downloads ETOPO bathymetry and Natural Earth coastline — ~30 min)
#
# Step 7 — seed grid coordinates into Kestra
#   make flow-keys
#   (seeds all 111 Gulf of Lion grid points into Kestra KV store)
#   (note: 9 of 111 are inland — excluded automatically in dbt)
#   (re-run this any time Docker volumes are reset or Kestra is restarted)
#
# Step 8 — validate the pipeline with one site before full backfill
#   make flow-test
#   (seeds KV store automatically, then ingests one site for one month)
#   (check Kestra UI at http://localhost:8080 to confirm it worked)
#   (only proceed to Step 9 if this passes)
#
# Step 9 — run full historical backfill
#   make flow-backfill
#   (ingests wind + wave for all 111 sites × 19 years — takes 2-4 hours)
#   (monitor progress at http://localhost:8080)
#   (DO NOT run make dbt until this completes)
#
# Step 10 — run dbt transformations
#   make dbt
#   (builds all models and runs 121 tests)
#   (expected output: 121/121 nodes passing)
#
# Step 11 — view results
#   open http://localhost:8080 to see Kestra execution history
#   open Looker Studio dashboard to see ranked sites
#
# ─────────────────────────────
# SHORTCUT — skip ingestion (data already in BigQuery):
#   make setup
#   make services
#   make wait
#   make flow-sync
#   make dbt
#
# ─────────────────────────────
# SUBSEQUENT RUNS:
#   make services    → start Kestra if stopped
#   make flow-sync   → update flows after editing YAML files
#   make flow-keys   → re-seed KV store if Docker was restarted
#   make dbt         → re-run transformations after data changes
#   make down        → stop all services when done
#
# TROUBLESHOOTING:
#   make flow-test   → use this to debug ingestion issues on a single site
#   make flow-sync   → run this if flows in Kestra UI don't match repo files
#   make clean       → reset venv and dbt artifacts if something breaks
# ============================================================