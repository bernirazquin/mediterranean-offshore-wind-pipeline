# ============================================================
# Gulf of Lion — Offshore Wind Pipeline
# ============================================================
# Usage:
#   make setup          → create venv and install dependencies
#   make infra          → provision GCP infrastructure via Terraform
#   make services       → start Kestra + dependencies via Docker Compose
#   make wait           → wait for Kestra to be healthy
#   make ingest         → load static reference data (bathymetry + coastline)
#   make ingest-test    → load minimal static data (Gulf of Lion only)
#   make flow-sync      → sync flow YAML files from repo to Kestra
#   make flow-keys      → seed KV store with config + 111 grid coordinates
#   make flow-test      → test ingestion for one site (validates pipeline)
#   make flow-mini      → ingest 3 sites x 1 year (test mode)
#   make flow-backfill  → full historical ingestion (~2-4 hours)
#   make flows          → flow-keys + flow-backfill together
#   make dbt            → run all dbt models and tests (full data)
#   make dbt-test       → run dbt models in test mode (3 sites, 2023 only)
#   make all            → full pipeline from scratch
#   make all-test       → full pipeline with minimal data (~5-10 min)
#   make down           → stop all services
#   make clean          → remove venv and dbt target
# ============================================================

# Load .env file if it exists
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Automation: encode credentials for Kestra and set path for Python SDK
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
DBT              = $(shell pwd)/.venv/bin/dbt

.DEFAULT_GOAL := help

.PHONY: all all-test setup infra services wait ingest ingest-test flows \
        flow-sync flow-keys flow-backfill flow-test flow-mini dbt dbt-test down clean help

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
	@echo "  make ingest-test    load minimal static data (Gulf of Lion only)"
	@echo "  make flow-sync      sync flow YAML files from repo to Kestra"
	@echo "  make flow-keys      seed KV store + 111 grid coordinates"
	@echo "  make flow-test      test ingestion for one site (run before backfill)"
	@echo "  make flow-mini      ingest 3 sites x 1 year (test mode)"
	@echo "  make flow-backfill  full historical ingestion (~2-4 hours)"
	@echo "  make flows          flow-keys + flow-backfill together"
	@echo "  make dbt            run all dbt models and tests (full data)"
	@echo "  make dbt-test       run dbt in test mode (3 sites, 2023 only)"
	@echo "  make all            full pipeline from scratch"
	@echo "  make all-test       full pipeline with minimal data (~5-10 min)"
	@echo "  make down           stop all services"
	@echo "  make clean          remove venv and dbt target"
	@echo ""

# ── Full pipeline ────────────────────────────────────────────
all: setup infra services wait flow-sync ingest flows dbt
	@echo "Pipeline complete."

# ── Full test pipeline (~5-10 min) ───────────────────────────
all-test: setup infra services wait flow-sync ingest-test flow-mini dbt-test
	@echo ""
	@echo "Test pipeline complete."
	@echo "For full dataset run: make all"

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
	@echo "Syncing Terraform state with GCP..."
	@which terraform > /dev/null 2>&1 || (echo "Terraform not found. Installing..." && \
		wget -q https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip -O /tmp/terraform.zip && \
		unzip -q /tmp/terraform.zip -d /tmp/terraform-bin && \
		sudo mv /tmp/terraform-bin/terraform /usr/local/bin/ && \
		rm -rf /tmp/terraform.zip /tmp/terraform-bin && \
		echo "Terraform installed.")
	@cd terraform && terraform init > /dev/null
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

# ── Static reference data — full ─────────────────────────────
ingest:
	@echo "Loading bathymetry data (~20 min)..."
	$(PYTHON) scripts/load_bathymetry.py
	@echo "Loading coastline distance data (~10 min)..."
	$(PYTHON) scripts/load_coastline_distance.py
	@echo "Static data loaded."

# ── Static reference data — test mode (Gulf of Lion only) ────
ingest-test:
	@echo "Loading static reference data in test mode (Gulf of Lion only)..."
	$(PYTHON) scripts/load_bathymetry.py --test
	$(PYTHON) scripts/load_coastline_distance.py --test
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

# ── Seed KV store with config + site coordinates ─────────────
flow-keys:
	@echo "Pushing GCS bucket and project ID to Kestra KV store..."
	@curl -s -u "$(KESTRA_AUTH)" -X PUT \
		"$(KESTRA_URL)/api/v1/kvs/$(KESTRA_NAMESPACE)/gcs_bucket" \
		-d "$(GCS_BUCKET)" \
		-H "Content-Type: text/plain" > /dev/null
	@curl -s -u "$(KESTRA_AUTH)" -X PUT \
		"$(KESTRA_URL)/api/v1/kvs/$(KESTRA_NAMESPACE)/gcp_project_id" \
		-d "$(GCP_PROJECT_ID)" \
		-H "Content-Type: text/plain" > /dev/null
	@echo "Seeding 111 grid coordinates into Kestra KV store..."
	@EXEC_ID=$$(curl -s -u "$(KESTRA_AUTH)" -X POST \
		"$(KESTRA_URL)/api/v1/executions/$(KESTRA_NAMESPACE)/site_key_values" \
		-H "Content-Type: application/json" \
		-d '{}' | python3 -c \
		"import sys,json; r=json.load(sys.stdin); print(r.get('id',''))"); \
	echo "  Execution ID: $$EXEC_ID"; \
	echo "  Waiting for KV store to be populated..."; \
	while true; do \
		STATE=$$(curl -s -u "$(KESTRA_AUTH)" \
			"$(KESTRA_URL)/api/v1/executions/$$EXEC_ID" | python3 -c \
			"import sys,json; print(json.load(sys.stdin).get('state',{}).get('current',''))"); \
		if [ "$$STATE" = "SUCCESS" ]; then echo "  KV store populated."; break; fi; \
		if [ "$$STATE" = "FAILED" ] || [ "$$STATE" = "KILLED" ]; then \
			echo "  ERROR: site_key_values flow failed (state: $$STATE)"; exit 1; fi; \
		sleep 5; \
	done

# ── Test ingestion — 3 sites x 1 year ────────────────────────
flow-mini:
	@echo "Injecting coordinates for 3 test sites into Kestra KV store..."
	@curl -s -u "$(KESTRA_AUTH)" -X PUT \
		"$(KESTRA_URL)/api/v1/namespaces/$(KESTRA_NAMESPACE)/kv/GULF_OF_LION_43.0_4.0" \
		-H "Content-Type: text/plain" \
		-d '{"lat": 43.0, "lon": 4.0}' > /dev/null
	@curl -s -u "$(KESTRA_AUTH)" -X PUT \
		"$(KESTRA_URL)/api/v1/namespaces/$(KESTRA_NAMESPACE)/kv/GULF_OF_LION_42.75_3.75" \
		-H "Content-Type: text/plain" \
		-d '{"lat": 42.75, "lon": 3.75}' > /dev/null
	@curl -s -u "$(KESTRA_AUTH)" -X PUT \
		"$(KESTRA_URL)/api/v1/namespaces/$(KESTRA_NAMESPACE)/kv/GULF_OF_LION_42.5_3.5" \
		-H "Content-Type: text/plain" \
		-d '{"lat": 42.5, "lon": 3.5}' > /dev/null
	@echo "Triggering mini ingestion — 3 sites x 1 year..."
	@EXEC_IDS=""; \
	for site in "GULF_OF_LION_43.0_4.0" "GULF_OF_LION_42.75_3.75" "GULF_OF_LION_42.5_3.5"; do \
		echo "  Ingesting $$site..."; \
		ID=$$(curl -s -u "$(KESTRA_AUTH)" -X POST \
			"$(KESTRA_URL)/api/v1/executions/$(KESTRA_NAMESPACE)/site_data_ingestion" \
			-H "Content-Type: multipart/form-data" \
			-F "site=$$site" \
			-F "start_date=2023-01-01" \
			-F "end_date=2023-12-31" | python3 -c \
			"import sys,json; print(json.load(sys.stdin).get('id',''))"); \
		echo "  Execution ID: $$ID"; \
		EXEC_IDS="$$EXEC_IDS $$ID"; \
	done; \
	echo "  Waiting for all 3 ingestions to complete..."; \
	for ID in $$EXEC_IDS; do \
		while true; do \
			STATE=$$(curl -s -u "$(KESTRA_AUTH)" \
				"$(KESTRA_URL)/api/v1/executions/$$ID" | python3 -c \
				"import sys,json; print(json.load(sys.stdin).get('state',{}).get('current',''))"); \
			if [ "$$STATE" = "SUCCESS" ]; then echo "  $$ID — SUCCESS"; break; fi; \
			if [ "$$STATE" = "FAILED" ] || [ "$$STATE" = "KILLED" ]; then \
				echo "  ERROR: execution $$ID failed (state: $$STATE)"; exit 1; fi; \
			sleep 5; \
		done; \
	done
	@echo "Mini ingestion complete."

# ── Test ingestion — 1 site x 1 month ────────────────────────
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

# ── Full historical backfill ──────────────────────────────────
flow-backfill:
	@echo "Triggering site_data_backfill (~2-4 hours)..."
	@echo "This ingests wind + wave data for all 111 sites x 19 years."
	@curl -s -u "$(KESTRA_AUTH)" -X POST \
		"$(KESTRA_URL)/api/v1/executions/$(KESTRA_NAMESPACE)/site_data_backfill" \
		-H "Content-Type: application/json" \
		-d '{}' | python3 -c \
		"import sys,json; r=json.load(sys.stdin); \
		print('  Execution ID:', r.get('id','unknown'))"
	@echo "Backfill triggered. Monitor at $(KESTRA_URL)"
	@echo "Run 'make dbt' after the backfill completes."

# ── Kestra flows — full ───────────────────────────────────────
flows: flow-keys flow-backfill
	@echo "All Kestra flows triggered."

# ── dbt — full data ───────────────────────────────────────────
dbt:
	@echo "Running dbt pipeline..."
	cd dbt && $(DBT) deps && $(DBT) seed && $(DBT) build --full-refresh --profiles-dir .
	@echo "dbt complete. Expected: 122/122 nodes passing."

# ── dbt — test mode (3 sites, 2023 only) ─────────────────────
dbt-test:
	@echo "Running dbt pipeline in TEST mode..."
	cd dbt && $(DBT) deps && $(DBT) seed && \
		$(DBT) build --full-refresh --vars 'is_test_run: true' --profiles-dir .
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
# SHORTCUT — 5-10 minute smoke test:
# ─────────────────────────────────────
#   1. cp .env.example .env
#      (fill in GCP_PROJECT_ID, GCS_BUCKET, GCP_SERVICE_ACCOUNT_B64)
#   2. Place your GCP JSON key at keys/google_credentials.json
#   3. make all-test
#
#   This runs the full pipeline with minimal data:
#   - Provisions GCP infrastructure via Terraform
#   - Starts Kestra via Docker Compose
#   - Loads Gulf of Lion bathymetry + coastline only
#   - Ingests 3 sites x 1 year via Kestra flows
#   - Runs all dbt models filtered to those 3 sites
#
# FULL PRODUCTION DEPLOYMENT:
# ─────────────────────────────────────
#   1. cp .env.example .env && fill in credentials
#   2. Place key at keys/google_credentials.json
#   3. make setup
#   4. make infra
#   5. make services && make wait
#   6. make flow-sync
#   7. make ingest           (~30 min)
#   8. make flow-keys
#   9. make flow-backfill    (~2-4 hours, monitor at http://localhost:8080)
#  10. make dbt
#
# SUBSEQUENT RUNS:
#   make services    → start Kestra if stopped
#   make flow-sync   → update flows after editing YAML files
#   make flow-keys   → re-seed KV store if Docker was restarted
#   make dbt         → re-run transformations after data changes
#   make down        → stop all services when done
#
# TROUBLESHOOTING:
#   make flow-test   → debug ingestion on a single site
#   make flow-sync   → fix flows if Kestra UI doesn't match repo
#   make clean       → reset venv and dbt artifacts
# ============================================================