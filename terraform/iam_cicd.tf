# This file defines the resources needed for the CI/CD pipeline itself.

# Service Account for GitHub Actions to use for deployment
resource "google_service_account" "github_actions_sa" {
  # Note: The account_id here matches the one you created manually.
  account_id   = "github-actions-deployer"
  display_name = "GitHub Actions Deployer SA"
  project      = var.gcp_project_id
}

# Grant the GitHub Actions SA permissions to deploy the infrastructure
resource "google_project_iam_member" "github_actions_editor" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.terraform_deployer.name
  member  = google_service_account.github_actions_sa.member
}