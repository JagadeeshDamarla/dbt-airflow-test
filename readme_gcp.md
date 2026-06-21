# Run dbt on GCP Managed Airflow (Cloud Composer) with Snowflake

This guide documents the architecture and deployment workflow for running dbt from Cloud Composer and loading data into Snowflake.

## 1) Architecture workflow

This is the intended end-to-end flow:

1. Make changes locally in this repository (DAG and dbt project).
2. Commit and push to GitHub.
3. GitHub Actions pipeline triggers on push (or manual dispatch).
4. GitHub Actions copies code to the Composer GCS bucket:
   - dags/ -> gs://<COMPOSER_BUCKET>/dags/
   - dbt_airflow_test/ -> gs://<COMPOSER_BUCKET>/data/dbt_airflow_test/
5. Cloud Composer automatically reads DAGs from the bucket dags/ prefix.
6. DAG appears in Airflow UI and runs on either:
   - manual trigger
   - configured schedule

Runtime path mapping used by your DAG:

- Composer worker path: /home/airflow/gcs/data/dbt_airflow_test
- GCS source path: gs://<COMPOSER_BUCKET>/data/dbt_airflow_test

## 2) IAM and permissions

Use least privilege where possible, but at minimum include these roles for deployment and runtime operations:

- Composer Administrator
- Composer Worker
- Logs Writer
- Storage Object Admin

Practical split by identity:

- Human/admin identity:
  - Composer Administrator
  - Storage Object Admin
- Composer environment service account:
  - Composer Worker
  - Logs Writer
  - Storage access required for Composer bucket usage
- GitHub Actions deployer service account (recommended separate SA):
  - Storage Object Admin on Composer bucket (or restricted to required prefixes)
  - Additional impersonation permissions if using Workload Identity Federation

Optional but common additions:

- Secret Manager accessor permissions if credentials are stored in Secret Manager.
- KMS decrypt permissions if CMEK is enabled.

## 3) GitHub Actions deployment model

Recommended approach:

1. Authenticate from GitHub Actions to GCP using Workload Identity Federation.
2. Validate changed content (optional lint/check step).
3. Sync DAG and dbt folders to the Composer bucket.
4. Confirm object upload and fail fast if sync fails.

Typical sync commands used by CI:

```bash
gsutil -m rsync -r dags gs://<COMPOSER_BUCKET>/dags
gsutil -m rsync -r dbt_airflow_test gs://<COMPOSER_BUCKET>/data/dbt_airflow_test
```

Recommended pipeline guardrails:

- Trigger on protected branches only (for example main).
- Require pull request checks before merge.
- Keep production deploy as a separate workflow or environment with approval.
- Add path filters so CI runs only when relevant files change:
  - dags/**
  - dbt_airflow_test/**

## 4) Composer Python packages (critical)

Do not rely on local virtual environments. dbt must be installed in Composer environment packages.

Install/pin:

- dbt-core==1.11.11
- dbt-snowflake==1.11.5
- protobuf>=4.25,<6

Why protobuf pin matters:

- dbt-core 1.11.x is not compatible with protobuf 6.x.
- Without this pin, runtime failures can occur (for example MessageToJson argument errors).

## 5) dbt profile and secrets

Your profile already uses environment variables in dbt_airflow_test/profiles.yml:

- SNOWFLAKE_ACCOUNT
- SNOWFLAKE_USER
- SNOWFLAKE_PASSWORD
- SNOWFLAKE_ROLE
- SNOWFLAKE_DATABASE
- SNOWFLAKE_WAREHOUSE
- SNOWFLAKE_SCHEMA

Your DAG injects these values from Airflow Variables.

Set these Airflow Variables:

- snowflake_account
- snowflake_user
- snowflake_password
- snowflake_role
- snowflake_database
- snowflake_warehouse
- snowflake_schema

For production, prefer Secret Manager backed retrieval over plain Variables for sensitive values.

## 6) DAG behavior and trigger modes

DAG file: dags/dbt_snowflake_dag.py

Task order:

- dbt_deps -> dbt_seed -> dbt_run -> dbt_test

Why this order matters:

- dbt_seed must run before dbt_run because model customer_seed_view.sql references seed customer_seed.

Execution modes:

- Manual run from Airflow UI for validation.
- Scheduled run by setting schedule_interval in DAG.

## 7) Validation checklist after CI deploy

1. Confirm latest DAG is visible in Airflow UI.
2. Trigger DAG manually once after deployment.
3. Verify logs for each task (deps, seed, run, test).
4. Validate resulting objects in Snowflake target schema.
5. Enable/confirm schedule only after stable manual run.

## 8) Troubleshooting quick list

No dbt output in task logs after command starts:

- dbt packages are missing in Composer environment.

protobuf/MessageToJson type errors:

- protobuf version is too high; keep protobuf below 6.

dbt project path errors:

- dbt folder was not copied to gs://<COMPOSER_BUCKET>/data/dbt_airflow_test.

Snowflake authentication/authorization errors:

- Incorrect Airflow Variables, missing Snowflake grants, or blocked network policy.

DAG present but run behavior differs from local:

- Local and Composer package versions are not aligned.
