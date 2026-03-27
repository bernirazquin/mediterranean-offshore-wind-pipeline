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
	@echo "Provisioning infrastructure..."
	cd terraform && terraform init && terraform apply -auto-approve
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
#
# Step 2 — set up Python environment
#   make setup
#
# Step 3 — provision GCP infrastructure
#   make infra
#   (creates GCS bucket and BigQuery datasets via Terraform)
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