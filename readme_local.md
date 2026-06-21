# Run Airflow Locally and Execute dbt in DAG

This guide explains how to run Airflow locally with Docker Compose and execute your dbt project from Airflow tasks.

## 1) Repository prerequisites

- Docker Desktop running.
- At least 4 GB memory and 2 CPU allocated to Docker.
- Open port 8080 for Airflow UI.

Your repository already contains:

- docker-compose.yaml
- dags/dbt_snowflake_dag.py
- dbt_airflow_test/ (dbt project)

The docker-compose file mounts your dbt project to:

- /home/airflow/gcs/data/dbt_airflow_test

This is the same path your DAG uses.

## 2) Package version strategy for local Airflow

Your local setup currently uses _PIP_ADDITIONAL_REQUIREMENTS with older dbt-snowflake version.
For reliable behavior, align local Airflow image dependencies with your target runtime.

Recommended versions:

- dbt-core==1.11.11
- dbt-snowflake==1.11.5
- protobuf>=4.25,<6

Important:

- Avoid protobuf 6.x with dbt-core 1.11.x.

## 3) Choose one way to install dbt in local Airflow containers

### Option A (recommended): build a custom Airflow image

1. Update Dockerfile to install pinned dbt packages.
2. In docker-compose.yaml, comment image and enable build.
3. Build and start services.

### Option B (quick tests): _PIP_ADDITIONAL_REQUIREMENTS in .env

Use _PIP_ADDITIONAL_REQUIREMENTS only for short-lived testing because packages are resolved at container startup.

## 4) Configure Snowflake credentials for local Airflow

Your DAG reads Airflow Variables and exports them as environment variables for dbt.
Set these in Airflow UI (Admin -> Variables):

- snowflake_account
- snowflake_user
- snowflake_password
- snowflake_role
- snowflake_database
- snowflake_warehouse
- snowflake_schema

Your dbt profile dbt_airflow_test/profiles.yml maps these to Snowflake connection fields.

## 5) Start local Airflow

From repository root:

```bash
docker compose up airflow-init
```

Then start all services:

```bash
docker compose up -d
```

Open Airflow UI:

- http://localhost:8080
- Default user/password in your compose setup: airflow / airflow (unless changed).

## 6) Confirm DAG and mounted paths

In Airflow UI:

- Verify DAG dbt_snowflake_pipeline appears.
- Verify it is not paused.

In container shell (optional verification):

```bash
docker compose exec airflow-worker ls -la /home/airflow/gcs/data/dbt_airflow_test
```

You should see dbt_project.yml and project folders.

## 7) DAG task flow and why it matters

Current flow is:

- dbt_deps -> dbt_seed -> dbt_run -> dbt_test

This order is correct for your project because model customer_seed_view.sql references seed customer_seed through ref().

> **Note:** `dbt debug` is intentionally skipped in the local setup. Running it locally caused git permissions errors, likely because dbt tries to resolve the git remote for version checks and the container environment does not have the necessary git credentials configured. It is safe to skip for local development — `dbt debug` is a connectivity/validity check and not required for model execution.

## 8) Trigger and validate

1. Trigger the DAG manually in Airflow UI.
2. Check each task log:
   - dbt_deps
   - dbt_seed
   - dbt_run
   - dbt_test
3. Validate resulting objects in Snowflake schema configured by variables.

## 9) Local troubleshooting

### 9.1 dbt command not found in task logs

Cause:

- dbt package not installed in Airflow containers.

Fix:

- Rebuild image (Option A) or update _PIP_ADDITIONAL_REQUIREMENTS (Option B), then restart containers.

### 9.2 protobuf / MessageToJson errors

Cause:

- protobuf 6.x installed.

Fix:

- Pin protobuf to >=4.25,<6 and restart/rebuild containers.

### 9.3 dbt cannot find profiles.yml

Cause:

- Wrong working directory or profiles-dir flag.

Fix:

- Ensure BashOperator uses:
  - cd /home/airflow/gcs/data/dbt_airflow_test
  - --profiles-dir .

### 9.4 Snowflake login/permission failures

Cause:

- Wrong variables or missing grants in Snowflake.

Fix:

- Validate Airflow Variables and Snowflake grants for role, warehouse, database, and schema.

### 9.5 DAG not visible in UI

Cause:

- DAG parse/import error.

Fix:

- Inspect scheduler logs:

```bash
docker compose logs airflow-scheduler --tail=200
```

## 10) Suggested production-hardening steps

- Add retries and retry_delay in DAG default_args.
- Add on_failure callbacks or alerts.
- Keep credentials out of plain Airflow Variables when possible.
- Use dbt selectors for targeted runs.
- Keep local and Composer package versions aligned.

## 11) Useful local commands

```bash
# Stop all services
docker compose down

# Stop and remove volumes (fresh reset)
docker compose down -v

# Rebuild images after dependency changes
docker compose build --no-cache

# Follow worker logs
docker compose logs -f airflow-worker

# Follow scheduler logs
docker compose logs -f airflow-scheduler
```
