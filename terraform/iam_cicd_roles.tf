# This file defines a custom IAM role for the CI/CD pipeline,
# adhering to the principle of least privilege.

resource "google_project_iam_custom_role" "terraform_deployer" {
  project     = var.gcp_project_id
  role_id     = "terraformDeployer"
  title       = "Terraform Deployer"
  description = "Custom role for the CI/CD pipeline to deploy the POS Ingestion application."
  permissions = [
    "bigquery.datasets.create",
    "bigquery.datasets.get",
    "bigquery.tables.create",
    "bigquery.tables.get",
    "bigquery.tables.update",
    "cloudfunctions.functions.create",
    "cloudfunctions.functions.get",
    "cloudfunctions.functions.update",
    "cloudscheduler.jobs.create",
    "cloudscheduler.jobs.get",
    "cloudscheduler.jobs.update",
    "iam.roles.get",
    "iam.roles.update",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.create",
    "iam.serviceAccountKeys.list",
    "run.services.setIamPolicy",
    "secretmanager.secrets.create",
    "secretmanager.secrets.get",
    "secretmanager.secrets.setIamPolicy",
    "storage.buckets.create",
    "storage.buckets.get",
    "storage.buckets.setIamPolicy",
    "storage.objects.create"
  ]
}