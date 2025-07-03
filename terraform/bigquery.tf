resource "google_bigquery_dataset" "pos_data" {
  dataset_id = "pos_data"
  location   = "US" # Or another location of your choice
  description = "Dataset for Point-of-Sale data"
}

locals {
  tables = {
    pos_checks = {
      schema_file = "checks.json", partitioned = true
    },
    pos_item_sales = {
      schema_file = "item_sales.json", partitioned = true
    },
    pos_time_records = {
      schema_file = "time_records.json", partitioned = true
    },
    pos_paidouts = {
      schema_file = "paidouts.json", partitioned = true
    },
    pos_customers = {
      schema_file = "customers.json", partitioned = false
    },
    pos_payments = {
      schema_file = "payments.json", partitioned = true
    },
    pos_item_sale_taxes = {
      schema_file = "item_sale_taxes.json", partitioned = true
    },
    pos_item_sale_components = {
      schema_file = "item_sale_components.json", partitioned = false # Example: not partitioned
    },
    pos_item_sale_adjustments = {
      schema_file = "item_sale_adjustments.json", partitioned = true
    },
    pos_check_gratuities = {
      schema_file = "check_gratuities.json", partitioned = false # Example: not partitioned
    }
  }
}

resource "google_bigquery_table" "tables" {
  for_each   = local.tables
  project    = var.gcp_project_id
  dataset_id = google_bigquery_dataset.pos_data.dataset_id
  table_id   = each.key

  schema = file("${path.module}/../schemas/${each.value.schema_file}")

  dynamic "time_partitioning" {
    for_each = each.value.partitioned ? [1] : []
    content {
      type  = "DAY"
      field = "business_date"
    }
  }

  # Deleting a table with this configuration will also delete its contents.
  deletion_protection = false
}