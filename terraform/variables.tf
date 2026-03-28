variable "credentials" {
  description = "credential file path for google cloud authentication"
  default     = "./keys/google_credentials.json"
}

variable "project" {
  description = "The unique GCP Project ID"
  default     = ""
}

variable "region" {
  description = "GCP Region"
  default     = "europe-west1"
}

variable "location" {
  description = "GCP Location for Storage and BigQuery"
  default     = "EU"
}

variable "gcs_bucket_name" {
  description = "Unique name for the GCS Bucket (Data Lake)"
  default     = ""
}

variable "bq_dataset_id" {
  description = "BigQuery Dataset ID (Data Warehouse)"
  default     = "med_wind_prod"
}