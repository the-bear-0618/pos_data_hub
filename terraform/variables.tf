variable "gcp_project_id" {
  description = "The GCP project ID to deploy resources to."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region for resources like Cloud Functions."
  type        = string
  default     = "us-central1"
}