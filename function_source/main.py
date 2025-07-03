import functions_framework
import os
import json
import logging
import requests
import re
import io
from datetime import datetime, timedelta, timezone

from google.cloud import bigquery
from google.cloud import secretmanager

# Configure logging
logging.basicConfig(level=logging.INFO)

# Initialize GCP clients in the global scope for reuse.
# This will cause a cold start to fail if not configured correctly,
# which is the desired behavior.
try:
    secret_manager_client = secretmanager.SecretManagerServiceClient()
    bq_client = bigquery.Client()
except Exception as e:
    logging.critical(f"Failed to initialize GCP clients: {e}")
    # Re-raise the exception to fail the function deployment/cold start
    raise

# --- Configuration ---
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
BIGQUERY_DATASET_ID = os.environ.get("BIGQUERY_DATASET_ID")
SITE_ID_SECRET_ID = os.environ.get("SITE_ID_SECRET_ID")
API_TOKEN_SECRET_ID = os.environ.get("API_TOKEN_SECRET_ID")

API_BASE_URL = "https://ecm-nsoeservices-bethpage.cbsnorthstar.com/reportservice/salesdata.svc"

ENDPOINT_TO_TABLE_MAP = {
    "checks": "pos_checks", # remains snake_case as per spec
    "itemSales": "pos_item_sales",
    "timeRecords": "pos_time_records",
    "paidouts": "pos_paidouts", # remains snake_case as per spec
    "customers": "pos_customers", # remains snake_case as per spec
    "payments": "pos_payments", # remains snake_case as per spec
    "itemSaleTaxes": "pos_item_sale_taxes",
    "itemSaleComponents": "pos_item_sale_components",
    "itemSaleAdjustments": "pos_item_sale_adjustments",
    "checkGratuities": "pos_check_gratuities",
}

# Define endpoints that do NOT require a date range. This is more maintainable,
# as new endpoints will be treated as time-series by default.
NON_TIME_SERIES_ENDPOINTS = {"customers"}

def _get_secret(secret_id: str) -> str:
    """Fetches the latest version of a secret from Secret Manager."""
    name = f"projects/{GCP_PROJECT_ID}/secrets/{secret_id}/versions/latest"
    try:
        response = secret_manager_client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        logging.error(f"Failed to access secret: {secret_id}. Error: {e}")
        raise

_snake_case_pattern1 = re.compile(r'(.)([A-Z][a-z]+)')
_snake_case_pattern2 = re.compile(r'([a-z0-9])([A-Z])')

def to_snake_case(name: str) -> str:
    """
    Converts a PascalCase or camelCase string to snake_case,
    correctly handling acronyms and consecutive capitals (e.g., 'checkID' -> 'check_id').
    """
    s1 = _snake_case_pattern1.sub(r'\1_\2', name)
    return _snake_case_pattern2.sub(r'\1_\2', s1).lower()

def _fetch_api_data(endpoint: str, params: dict) -> list | None:
    """Fetches data from a single API endpoint."""
    api_url = f"{API_BASE_URL}/{endpoint}"
    try:
        response = requests.get(api_url, params=params, timeout=60)
        response.raise_for_status()  # Raises an HTTPError for bad responses (4xx or 5xx)
        data = response.json()
        if not isinstance(data, list) or not data:
            logging.warning(f"No data returned for endpoint {endpoint}. Response: {data}")
            return None
        return data
    except requests.exceptions.RequestException as e:
        logging.error(f"API call failed for endpoint {endpoint}. Error: {e}")
    except json.JSONDecodeError:
        logging.error(f"Failed to decode JSON for endpoint {endpoint}. Response text: {response.text[:500]}")
    return None

def _load_data_to_bigquery(data: list, table_name: str):
    """Transforms and loads a list of records into a BigQuery table."""
    try:
        # Create a generator to transform records on-the-fly, which is more memory-efficient.
        ingestion_time = datetime.now(timezone.utc).isoformat()
        def transform_generator(records):
            for record in records:
                snake_case_record = {to_snake_case(k): v for k, v in record.items()}
                snake_case_record["ingestion_timestamp"] = ingestion_time
                yield snake_case_record

        json_string_generator = (json.dumps(record) for record in transform_generator(data))
        ndjson_data = "\n".join(json_string_generator)
        data_as_file = io.StringIO(ndjson_data)

        table_ref = f"{GCP_PROJECT_ID}.{BIGQUERY_DATASET_ID}.{table_name}"
        
        job_config = bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            ignore_unknown_values=True,
            autodetect=False, 
        )

        logging.info(f"Loading {len(data)} rows into BigQuery table: {table_ref}")
        load_job = bq_client.load_table_from_file(
            data_as_file, table_ref, job_config=job_config
        )
        
        load_job.result() # Wait for the job to complete

        if load_job.errors:
            logging.error(f"BigQuery load job failed for {table_ref}. Errors: {load_job.errors}")
        else:
            logging.info(f"Successfully loaded {load_job.output_rows} rows to {table_ref}")

    except Exception as e:
        logging.error(f"An error occurred during BigQuery load for table {table_name}. Error: {e}")

@functions_framework.http
def ingest_pos_data(request):
    """HTTP Cloud Function to ingest POS data from an API to BigQuery."""
    # --- 1. Fetch API Credentials ---
    try:
        site_id = _get_secret(SITE_ID_SECRET_ID)
        api_access_token = _get_secret(API_TOKEN_SECRET_ID)
    except Exception:
        return "Failed to retrieve API credentials from Secret Manager", 500

    # --- 2. Determine Date Range ---
    request_json = request.get_json(silent=True) or {}
    days_back = int(request_json.get("days_back", 1))
    
    end_date = datetime.now(timezone.utc).date()
    start_date = end_date - timedelta(days=days_back)
    
    start_date_str = start_date.strftime("%Y-%m-%d")
    end_date_str = end_date.strftime("%Y-%m-%d")
    logging.info(f"Processing data for date range: {start_date_str} to {end_date_str}")

    # --- 3. Process Each Endpoint ---
    for endpoint, table_name in ENDPOINT_TO_TABLE_MAP.items():
        logging.info(f"--- Starting process for endpoint: {endpoint} ---")

        # --- 3a. Construct API Request ---
        params = {"siteid": site_id, "accesstoken": api_access_token}
        if endpoint not in NON_TIME_SERIES_ENDPOINTS:
            params["startdate"] = start_date_str
            params["enddate"] = end_date_str
        
        # --- 3b. Fetch and Load Data ---
        data = _fetch_api_data(endpoint, params)
        if data:
            _load_data_to_bigquery(data, table_name)
        else:
            logging.warning(f"Skipping BigQuery load for {endpoint} due to no data.")
            continue

    logging.info("Data ingestion process completed.")
    return "OK", 200