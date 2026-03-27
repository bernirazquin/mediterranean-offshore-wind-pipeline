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
#   make flow-test      → test ingestion for one site (validates pipeline)
#   make flow-backfill  → full historical ingestion (~2-4 hours)
#   make flows          → flow-keys + flow-backfill together
#   make dbt            → run all dbt models and tests (Full Data)
#   make all            → full pipeline from scratch
#   make all-test       → full pipeline with minimal data (~5 min)
#   make down           → stop all services
#   make clean          → remove venv and dbt target
# ============================================================

# Load .env file if it exists
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Automation: If the credentials file exists, encode it to B64 for Kestra 
# AND set the path for the Python SDK
ifeq (,$(wildcard keys/google_credentials.json))
    $(error "GCP key not found at keys/google_credentials.json. Please add it.")
else
    export GCP_SERVICE_ACCOUNT_B64 ?= $(shell base64 -w 0 keys/google_credentials.json)
    export GOOGLE_APPLICATION_CREDENTIALS = $(shell pwd)/keys/google_credentials.json
endif

KESTRA_URL       = http://localhost:8080
KESTRA_NAMESPACE = company.wind
KESTRA_USER      = admin@wind.com
KESTRA_PASSWORD  = Admin1234!
KESTRA_AUTH      = $(KESTRA_USER):$(KESTRA_PASSWORD)

VENV             = .venv
PYTHON           = $(VENV)/bin/python
PIP              = $(VENV)/bin/pip
DBT              = $(VENV)/bin/dbt

.DEFAULT_GOAL := help

.PHONY: all all-test setup infra services wait ingest ingest-test flows \
        flow-sync flow-keys flow-backfill flow-test flow-mini dbt dbt-test down clean help

# ── Help ─────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Gulf of Lion — Offshore Wind Pipeline"
	@echo "======================================"
	@echo "  make setup         create venv and install dependencies"
	@echo "  make infra         provision GCP infrastructure via Terraform"
	@echo "  make services      start Kestra + dependencies via Docker Compose"
	@echo "  make wait          wait for Kestra to be healthy"
	@echo "  make ingest        load bathymetry + coastline (~30 min)"
	@echo "  make ingest-test   load test data for ingestion testing (Gulf of Lion only)"
	@echo "  make flow-sync     sync flow YAML files from repo to Kestra"
	@echo "  make flow-keys     seed 111 grid coordinates into Kestra KV store"
	@echo "  make flow-test     test ingestion for one site (run before backfill)"
	@echo "  make flow-backfill full historical ingestion (~2-4 hours)"
	@echo "  make flows         flow-keys + flow-backfill together"
	@echo "  make dbt           run all dbt models and tests (Full Data)"
	@echo "  make dbt-test      run dbt models for test data (Minimal Data)"
	@echo "  make all           full pipeline from scratch"
	@echo "  make all-test      full pipeline with minimal data (~5 min)"
	@echo "  make down          stop all services"
	@echo "  make clean         remove venv and dbt target"
	@echo ""

# ── Full pipeline ────────────────────────────────────────────
all: setup infra services wait ingest flow-sync flows dbt
	@echo "Pipeline complete."

# ── Full test pipeline (under 5 min) ─────────────────────────
all-test: setup infra services wait flow-sync ingest-test flow-mini dbt-test
	@echo "Test pipeline complete. To run full dataset: run 'make all' instead."

ingest-test:
	@echo "Loading static reference data in test mode (Gulf of Lion only)..."
	$(PYTHON) scripts/load_bathymetry.py --test
	$(PYTHON) scripts/load_coastline_distance.py --test
	@echo "Static data loaded."

# ── Seed Kestra with .env values + Site Coordinates ──────────
flow-keys:
	@echo "Pushing configuration to Kestra KV store..."
	@curl -s -u "$(KESTRA_AUTH)" -X PUT $(KESTRA_URL)/api/v1/kvs/$(KESTRA_NAMESPACE)/gcs_bucket -d "$(GCS_BUCKET)" -H "Content-Type: text/plain"
	@curl -s -u "$(KESTRA_AUTH)" -X PUT $(KESTRA_URL)/api/v1/kvs/$(KESTRA_NAMESPACE)/gcp_project_id -d "$(GCP_PROJECT_ID)" -H "Content-Type: text/plain"
	@echo "Seeding 111 grid coordinates into Kestra..."
	@curl -s -u "$(KESTRA_AUTH)" -X POST \
		"$(KESTRA_URL)/api/v1/executions/$(KESTRA_NAMESPACE)/site_key_values" \
		-H "Content-Type: application/json" -d '{}' | python3 -c \
		"import sys,json; r=json.load(sys.stdin); print('  Execution ID:', r.get('id','unknown'))"
	@echo "Waiting 30s for coordinate seeding to finish..."
	@sleep 30

# ── Trigger 3-Site Test ──────────────────────────────────────
flow-mini: flow-keys
	@echo "Triggering mini ingestion — 3 sites x 1 year..."
	@for site in "GULF_OF_LION_43.0_4.0" "GULF_OF_LION_42.75_3.75" "GULF_OF_LION_42.5_3.5"; do \
		echo "  Ingesting $$site..."; \
		curl -s -u "$(KESTRA_AUTH)" -X POST \
			"$(KESTRA_URL)/api/v1/executions/$(KESTRA_NAMESPACE)/site_data_ingestion" \
			-H "Content-Type: multipart/form-data" \
			-F "site=$$site" \
			-F "start_date=2023-01-01" \
			-F "end_date=2023-12-31" | python3 -c \
			"import sys,json; r=json.load(sys.stdin); print('  Execution ID:', r.get('id','unknown'))"; \
	done
	@echo "Waiting 180s for ingestion to complete..."
	@sleep 180
	@echo "Mini ingestion complete."

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
	@test -f keys/google_credentials.json || (echo "ERROR: Key missing"; exit 1)
	
	@echo "Syncing Terraform state with GCP..."
	@cd terraform && terraform init > /dev/null
	
	# If the dataset exists but isn't in state, import it silently
	-@cd terraform && terraform import \
		-var="project=$(GCP_PROJECT_ID)" \
		-var="gcs_bucket_name=$(GCS_BUCKET)" \
		-var="credentials=../keys/google_credentials.json" \
		google_bigquery_dataset.dataset \
		projects/$(GCP_PROJECT_ID)/datasets/med_wind_prod 2>/dev/null || true

	@echo "Provisioning infrastructure..."
	cd terraform && terraform apply -auto-approve \
		-var="project=$(GCP_PROJECT_ID)" \
		-var="gcs_bucket_name=$(GCS_BUCKET)" \
		-var="credentials=../keys/google_credentials.json"

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
			--data-binary "@$$flow" > /dev/null; \
		echo "  Done."; \
	done
	@echo "Flows synced."

# ── Kestra flows ─────────────────────────────────────────────
flows: flow-keys flow-backfill
	@echo "All Kestra flows triggered."

flow-keys:
	@echo "Seeding 111 grid coordinates into Kestra KV store..."
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
	@curl -s -u "$(KESTRA_AUTH)" -X POST \
		"$(KESTRA_URL)/api/v1/executions/$(KESTRA_NAMESPACE)/site_data_backfill" \
		-H "Content-Type: application/json" \
		-d '{}' | python3 -c \
		"import sys,json; r=json.load(sys.stdin); \
		print('  Execution ID:', r.get('id','unknown'))"
	@echo "Backfill triggered. Monitor at $(KESTRA_URL)"

# ── dbt ──────────────────────────────────────────────────────
dbt:
	@echo "Running dbt pipeline..."
	cd dbt && $(DBT) deps && $(DBT) seed && $(DBT) build --full-refresh
	@echo "dbt complete. Expected: 121/121 nodes passing."

dbt-test:
	@echo "Running dbt pipeline in TEST mode..."
	cd dbt && $(DBT) deps && $(DBT) seed && \
		$(DBT) build --full-refresh --vars 'is_test_run: true'
	@echo "dbt test complete."
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
# 🚀 SHORTCUT: THE 5-MINUTE SMOKE TEST
# ─────────────────────────────
# If you want to see the entire stack working without waiting hours:
# 1. cp .env.example .env (and fill in your GCP details)
# 2. Place GCP JSON key in keys/google_credentials.json
# 3. Run: make all-test
# 
# This command automatically performs:
# - Python setup & Infrastructure provisioning
# - Kestra startup & Flow synchronization
# - Minimal bathymetry/coastline ingestion (Gulf of Lion only)
# - Ingestion of 3 sites for the year 2023
# - dbt transformation on the filtered 2023 dataset
#
# 🏗️ FULL PRODUCTION DEPLOYMENT
# ─────────────────────────────
# Step 1 — set up environment & infra
#   make setup && make infra
#
# Step 2 — start Kestra
#   make services && make wait
#
# Step 3 — sync flows & load full static data (~30 min)
#   make flow-sync && make ingest
#
# Step 4 — seed grid & run full backfill (~2-4 hours)
#   make flow-keys && make flow-backfill
#
# Step 5 — run dbt transformations
#   make dbt
# ============================================================