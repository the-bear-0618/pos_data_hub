# Service Account for the Cloud Function to run as
resource "google_service_account" "pos_ingestion_sa" {
  account_id   = "pos-ingestion-sa"
  display_name = "POS Data Ingestion Service Account"
  project      = var.gcp_project_id
}

# Grant the SA permissions to write to BigQuery
resource "google_project_iam_member" "bq_data_editor" {
  project = var.gcp_project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_service_account.pos_ingestion_sa.member
}

# Grant the SA permissions to read from Secret Manager
resource "google_project_iam_member" "secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = google_service_account.pos_ingestion_sa.member
}