# dbt Practices — rock_logistics_inbound

Conventions for writing, structuring, and maintaining dbt models in this repo. Applies to all projects under `src/dbt/`.

---

## Table of Contents
1. [Project Structure](#1-project-structure)
2. [Naming Conventions](#2-naming-conventions)
3. [DBT Configurations](#3-dbt-configurations)
4. [Custom Macros](#4-custom-macros)
5. [Documentation & Schema YAML](#5-documentation--schema-yaml)
6. [Shared Models](#6-shared-models)
7. [Git & Pull Request Conventions](#7-git--pull-request-conventions)

---

## 1. Project Structure

Each dbt project under `src/dbt/` follows this layout:

```
<project_name>/
  dbt_project.yml       # project config: name, model-paths, materialization defaults
  profiles.yml          # Snowflake connection (points to tst by default)
  Dockerfile            # Cloud Run image
  models/
    tables/             # materialized tables (incremental, merge_into_insert)
    views/              # V_* staging views
    # outbound also has: bridges/, dimensions/, facts/, secure/, dataproducts/
  macros/               # custom materializations and helper macros
  <model>.yml           # column descriptions alongside the SQL file
```

- `profiles.yml` always targets `tst` as the default — switching to `prd` requires explicit env override.
- `PRIVATE_KEY` must be set in the environment before running `dbt run` (injected by Cloud Run at runtime, or by `run_dbt_pipeline.sh` locally).

---

## 2. Naming Conventions

### SQL Naming

- Follow `snake_case` for column names, schema names, and stage names.

### Model Files

| Type | Convention | Example |
|---|---|---|
| Views (staging) | `V_` prefix, `UPPER_SNAKE_CASE` | `V_INBOUND_MODEL.sql` |
| Current-state tables | `UPPER_SNAKE_CASE` | `INBOUND_MODEL.sql` |
| History tables | `_HIST` suffix | `BRIDGE_RECEIPTS_HIST.sql` |
| Delta / deleted tracking | `_DLT` suffix | `BRIDGE_STOCK_NOTIFICATIONS_DLT.sql` |
| Materialized from view | `_MAT` suffix | `STOCK_PARTNER_VARIATION_IST_MAT.sql` |
| Dimensions | `DIM_` prefix | `DIM_ARTICLE.sql` |
| Facts | `FACT_` prefix | `FACT_PACKAGES.sql` |
| Bridge tables | `BRIDGE_` prefix | `BRIDGE_RECEIPTS.sql` |
| Data products | `DP_` prefix | `DP_STOCKANALYSIS_STOCK.sql` |
| Staging (temporary) | `STG_` prefix | `STG_ARTICLE_DATA.sql` |

### Other Files

| Type | Convention | Example |
|---|---|---|
| Macro files | `snake_case.sql` | `merge_into_insert.sql` |
| Schema / doc files | same name as model | `BRIDGE_RECEIPTS_HIST.yml` |
| dbt project name | matches directory name | `inbound_full`, `stock_model` |

---

## 3. DBT Configurations

### Model Config Block Style

Use **comma-first** style for multi-line config blocks:

```sql
{{config(materialized='merge_into_insert', unique_key=['HASHDIFF'], snowflake_warehouse='WH_ROCK_MEDIUM_1', tags=['step1'])}}
```

---

### Tags & Selective Execution

Tags control which models are included in a `dbt run --select tag:<value>` call.

**Rules:**
- Assign tags that reflect the **pipeline or execution group** the model belongs to, not the model type.
- For ordered step execution within a pipeline, use `step1`, `step2`, etc.:
  ```sql
  , tags=['step1']
  ```
- Add Snowflake query tagging for traceability with project identifier (for example a project id in `query_tag`) so query history can be filtered per project run.

---

### Patterns

Every materialized table has a corresponding **view** that holds all the transformation logic:

```
V_INBOUND_MODEL.sql      ← all SQL logic lives here (CTEs, joins, filters)
        ↓
INBOUND_MODEL.sql        ← selects needed columns from {{ ref("V_INBOUND_MODEL") }}
```

**Rules:**
- Table models contain **no business logic** — select only the columns needed from the upstream view.
- Do **not** use `SELECT *` — explicitly list required columns to improve clarity and reduce accidental column carries.
- All joins, filters, calculations, and transformations belong in the view.
- This separation makes it easy to inspect the logic (run the view) without waiting for a full table materialization.

---

### Materializations

### Overview

| Materialization | When to use |
|---|---|
| `view` (default) | Staging / intermediate layer — all `V_*` models |
| `incremental` + `append` + `pre_hook truncate` | Current-state tables — full reload every run |
| `merge_into_insert` (custom) | History tables (`*_HIST`) — insert-only, rows never updated |
| `merge_into_insert_wo_hashdiff` (custom) | History tables that don't carry a `HASHDIFF` column |
| `table` | Declared at project level in `dbt_project.yml` for simple materialized views |

---

### `incremental` — Full Reload Pattern

Used for tables that represent **current state only**. Despite using `incremental`, the pre-hook truncates the table on every run, making it a full reload. The `incremental` materialization is used only to avoid the `CREATE TABLE` DDL overhead on repeat runs.

```sql
{{
    config(
        materialized="incremental"
        , incremental_strategy="append"
        , snowflake_warehouse='WH_ROCK_MEDIUM_1'
        , pre_hook=[
            "CREATE TABLE {{ this }}_{{ run_started_at.strftime('%Y%m%d%H%M%S') }} AS SELECT * FROM {{ this }};",
            "truncate table {{ this }}"
        ]
        , tags=['il_inbound_full']
    )
}}
```

**Rules:**
- Always use `incremental_strategy="append"` — never `merge` or `delete+insert` with this pattern.
- The first pre-hook creates a **timestamped backup** before truncating. This is a safety net for recovery — do not remove it.
- If an incremental model uses a pre-hook temporary table, include an explicit cleanup strategy (`DROP TABLE IF EXISTS`) in a post-hook or in the run workflow.
- Never add a `WHEN is_incremental()` block — these models always reload in full.

---

### `merge_into_insert` — History Table Pattern

Used for `*_HIST` tables that must **only grow**. Once a row is written, it is never updated or deleted. Rows are deduplicated by `HASHDIFF`.

```sql
{{
    config(
        materialized='merge_into_insert'
        , unique_key=['HASHDIFF']
        , snowflake_warehouse='WH_ROCK_MEDIUM_1'
        , tags=['step1']
    )
}}
select * from {{ ref("BRIDGE_STOCK_NOTIFICATIONS_DLT") }}
```

**How it works internally:**
1. Runs the model SQL into a temporary table (`<model>_tmp`).
2. Executes a `MERGE INTO` the target using the `unique_key` columns.
3. Only `WHEN NOT MATCHED THEN INSERT` — no `WHEN MATCHED` clause, so existing rows are silently skipped.

**Rules:**
- `unique_key` is **required** — the macro calls `config.require('unique_key')` and will fail without it.
- `HASHDIFF` is the standard deduplication key (a hash of all business columns). Use it unless the model explicitly uses `merge_into_insert_wo_hashdiff`.
- The source model for a `_HIST` table is typically a `_DLT` (delta) view that only produces new/changed rows.

---

### `merge_into_insert_wo_hashdiff` — History Without Hash

Same MERGE-insert-only logic as `merge_into_insert` but for tables that don't use a `HASHDIFF` column. The `unique_key` is set to the business primary key columns directly.

---

## 4. Custom Macros

All custom materializations are Snowflake-specific (`adapter="snowflake"`) and live in each project's `macros/` directory.

### Writing a Macro
- Use `config.require('param')` for mandatory config params — it raises a clear error if missing.
- Create a temporary table for the model SQL, then operate on it — never run the model SQL inline multiple times.
- Always `{{ return({'relations': [this]}) }}` at the end so dbt tracks the relation.
- Log key steps with `{{ log("message", info=True) }}` for visibility in dbt run output.

### Modifying Existing Macros
- `merge_into_insert.sql` and `merge_into_insert_wo_hashdiff.sql` are used by many models across multiple projects — test any change in `tst` before merging.
- Do not add `WHEN MATCHED THEN UPDATE` to `merge_into_insert` — the insert-only behaviour is intentional for history tables.

---

## 5. Documentation & Schema YAML

Every project sets:
```yaml
# dbt_project.yml
persist_docs:
  relation: true
  columns: true
```

This means dbt persists descriptions directly to Snowflake as object comments. As a result:
- **Every model** must have a `.yml` file with a `description`.
- **Every column** in a table model must be described.
- View models should be described but column-level docs are optional if the downstream table covers them.

Minimal example:
```yaml
version: 2

models:
  - name: BRIDGE_RECEIPTS_HIST
    description: "Historical snapshot of receipt bridge records. Insert-only via merge_into_insert."
    columns:
      - name: HASHDIFF
        description: "SHA hash of all business columns. Used as the unique key for deduplication."
      - name: RECEIPT_ID
        description: "Unique identifier for the receipt."
```

---

## 6. Shared Models

- Reusable SQL views shared across multiple dbt projects live in `src/dbt/_shared_models/`.
- They are included in each project via `model-paths` in `dbt_project.yml`:
  ```yaml
  model-paths: ["models", "../_shared_models"]
  ```
- **Do not copy or duplicate** SQL from `_shared_models` into project-specific model files.
- If a model is only used by one project, it stays inside that project's `models/` directory.

---

## 7. Git & Pull Request Conventions

### Branch Naming
```
<type>/<short-description>
```
| Type | When to use |
|---|---|
| `feat/` | New pipeline or new model |
| `fix/` | Bug fix in existing pipeline |
| `chore/` | Terraform, Dockerfile, CI changes |
| `refactor/` | Code restructuring without behavior change |
| `docs/` | Documentation-only changes |

Examples: `feat/inbound-prioritization-v2`, `fix/tm1-hourly-key-error`, `chore/update-python-3-14`

### Commit Messages
Follow the **Conventional Commits** format:
```
<type>(<scope>): <short summary>

[optional body]
```
- `<type>`: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`
- `<scope>`: pipeline or module name (`inbound_ekr_inf`, `dbt/inbound_full`, `terraform`)
- Summary: imperative mood, lowercase, no period — "add retry logic" not "Added retry logic."

Examples:
```
feat(inbound_ekr_inf): add incremental load by LOAD_TS
fix(dbt/inbound_full): correct HASHDIFF column in BRIDGE_RECEIPTS
chore(terraform): upgrade Cloud Run job timeout to 10800s
```

### Pull Request Rules
- **One pipeline per PR** unless changes are truly cross-cutting (e.g., base handler fix).
- PR title follows the same Conventional Commits format as commit messages.
- Every PR must include:
  - A description of what changed and why.
  - Steps to test / validate (e.g., "ran `dbt run --select tag:step1` in `tst`").
  - Reference to the relevant ticket/issue if one exists.
- Minimum **1 reviewer** before merge; 2 reviewers for `prd`-impacting changes.
- Do not merge with failing CI checks.
- Delete the branch after merge.

### Important — No Direct Commits to Main
- **Pushing directly to `main` is prohibited** for all developers.
- Every change must go through a branch and be reviewed via a PR before merging.
- This ensures code quality, traceability, and prevents accidental deployments.
