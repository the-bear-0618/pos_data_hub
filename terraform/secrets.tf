resource "google_secret_manager_secret" "site_id" {
  secret_id = "pos-site-id"
  project   = var.gcp_project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "api_token" {
  secret_id = "pos-api-token"
  project   = var.gcp_project_id

  replication {
    auto {}
  }
}