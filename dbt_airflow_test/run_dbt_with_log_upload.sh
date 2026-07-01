#!/usr/bin/env bash

set -u

DBT_DIR="/usr/app/dbt"
DBT_EXIT_CODE=0

build_dbt_vars_json() {
  python - <<'PY'
import json
import os

vars_payload = {}
from_date = os.getenv("DBT_FROM_DATE", "").strip()
to_date = os.getenv("DBT_TO_DATE", "").strip()

if not from_date or not to_date:
  raise SystemExit("DBT_FROM_DATE and DBT_TO_DATE are required.")

vars_payload["from_date"] = from_date
vars_payload["to_date"] = to_date

print(json.dumps(vars_payload, separators=(",", ":")))
PY
}

run_dbt() {
  cd "$DBT_DIR" || return 1

  local dbt_vars_json
  dbt_vars_json="$(build_dbt_vars_json)"
  echo "Running dbt build with vars: ${dbt_vars_json}"

  dbt build --vars "$dbt_vars_json"
}

upload_logs_to_gcs() {
  local bucket_name="${DBT_LOG_BUCKET:-dbt_logs_test_2026}"
  local current_date
  local current_hour
  local timestamp
  local execution_id
  local gcs_prefix

  current_date="$(date -u +%Y-%m-%d)"
  current_hour="$(date -u +%H)"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  execution_id="${CLOUD_RUN_EXECUTION:-manual-execution}"
  gcs_prefix="${current_date}/${current_hour}/${execution_id}-${timestamp}"

  echo "Uploading dbt logs to gs://${bucket_name}/${gcs_prefix}/"

  BUCKET_NAME="$bucket_name" GCS_PREFIX="$gcs_prefix" DBT_DIR="$DBT_DIR" python - <<'PY'
import os
from pathlib import Path

from google.cloud import storage

bucket_name = os.environ["BUCKET_NAME"]
gcs_prefix = os.environ["GCS_PREFIX"].strip("/")
dbt_dir = Path(os.environ["DBT_DIR"])

candidate_paths = [
    dbt_dir / "logs",
    dbt_dir / "target" / "run_results.json",
    dbt_dir / "target" / "manifest.json",
    dbt_dir / "target" / "perf_info.json",
]

files_to_upload = []
for path in candidate_paths:
    if path.is_dir():
        for file_path in path.rglob("*"):
            if file_path.is_file():
                relative = file_path.relative_to(dbt_dir)
                files_to_upload.append((file_path, relative))
    elif path.is_file():
        relative = path.relative_to(dbt_dir)
        files_to_upload.append((path, relative))

if not files_to_upload:
    print("No dbt log artifacts found to upload.")
    raise SystemExit(0)

client = storage.Client()
bucket = client.bucket(bucket_name)

for local_file, relative_path in files_to_upload:
    blob_name = f"{gcs_prefix}/{relative_path.as_posix()}"
    blob = bucket.blob(blob_name)
    blob.upload_from_filename(str(local_file))
    print(f"Uploaded {local_file} -> gs://{bucket_name}/{blob_name}")
PY
}

run_dbt || DBT_EXIT_CODE=$?

if ! upload_logs_to_gcs; then
  echo "WARNING: Failed to upload dbt artifacts to GCS bucket ${DBT_LOG_BUCKET:-dbt_logs_test_2026}."
fi

exit "$DBT_EXIT_CODE"
