resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Zip the function source code
data "archive_file" "source" {
  type        = "zip"
  source_dir  = "${path.module}/../function_source"
  output_path = "${path.module}/function_source.zip"
}

# Bucket to store the zipped source code
resource "google_storage_bucket" "function_source_bucket" {
  name                        = "${var.gcp_project_id}-pos-function-source-${random_id.bucket_suffix.hex}"
  location                    = var.gcp_region
  uniform_bucket_level_access = true
}

# Upload the zipped source code to the bucket
resource "google_storage_bucket_object" "source_archive" {
  name   = "source.zip#${data.archive_file.source.output_md5}"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.source.output_path
}

# Cloud Function (2nd Gen)
resource "google_cloudfunctions2_function" "pos_ingestion" {
  name     = "pos-data-ingestion"
  location = var.gcp_region

  build_config {
    runtime     = "python311"
    entry_point = "ingest_pos_data"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.source_archive.name
      }
    }
  }

  service_config {
    max_instance_count = 3
    min_instance_count = 0
    timeout_seconds    = 300
    service_account_email = google_service_account.pos_ingestion_sa.email
    environment_variables = {
      GCP_PROJECT_ID        = var.gcp_project_id
      BIGQUERY_DATASET_ID   = google_bigquery_dataset.pos_data.dataset_id
      SITE_ID_SECRET_ID     = google_secret_manager_secret.site_id.secret_id
      API_TOKEN_SECRET_ID   = google_secret_manager_secret.api_token.secret_id
    }
  }
}

# Grant the Service Account permission to invoke the underlying Cloud Run service (needed for OIDC)
resource "google_cloud_run_service_iam_member" "invoker" {
  project  = google_cloudfunctions2_function.pos_ingestion.project
  location = google_cloudfunctions2_function.pos_ingestion.location
  service  = google_cloudfunctions2_function.pos_ingestion.name # For 2nd gen, the service name matches the function name
  role     = "roles/run.invoker"
  member   = google_service_account.pos_ingestion_sa.member
}

# Cloud Scheduler job to trigger the function every 15 minutes
resource "google_cloud_scheduler_job" "invoke_pos_ingestion" {
  name     = "invoke-pos-ingestion-function"
  schedule = "*/15 * * * *" # Every fifteen minutes
  time_zone = "UTC"

  http_target {
    uri         = google_cloudfunctions2_function.pos_ingestion.service_config[0].uri
    http_method = "POST"
    body        = base64encode("{\"days_back\": 1}")
    oidc_token {
      service_account_email = google_service_account.pos_ingestion_sa.email
    }
  }
}