terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.6.0"
    }
  }
}

provider "google" {
  credentials = file(var.credentials)
  project     = var.project
  region      = var.region
}

# Data Lake: Google Cloud Storage Bucket (raw data)
resource "google_storage_bucket" "data-lake-bucket" {
  # Concatenating project ID to ensure global uniqueness
  name          = "${var.gcs_bucket_name}_${var.project}"
  location      = var.location
  force_destroy = true

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

# Data Warehouse: BigQuery Dataset (clean, queriable data)
resource "google_bigquery_dataset" "dataset" {
  dataset_id = var.bq_dataset_id
  location   = var.location
}