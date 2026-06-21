from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta
import os

# Path where Composer mounts the 'data' folder inside the worker
DBT_PROJECT_DIR = '/home/airflow/gcs/data/dbt_airflow_test'

global_dbt_env = os.environ.copy()

global_dbt_env.update({
    'SNOWFLAKE_ACCOUNT': '{{ var.value.get("snowflake_account") }}',
    'SNOWFLAKE_USER': '{{ var.value.get("snowflake_user") }}',
    'SNOWFLAKE_PASSWORD': '{{ var.value.get("snowflake_password") }}',
    'SNOWFLAKE_ROLE': '{{ var.value.get("snowflake_role") }}',
    'SNOWFLAKE_DATABASE': '{{ var.value.get("snowflake_database") }}',
    'SNOWFLAKE_WAREHOUSE': '{{ var.value.get("snowflake_warehouse") }}',
    'SNOWFLAKE_SCHEMA': '{{ var.value.get("snowflake_schema") }}'
})

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'retries': 0, # Keep at 0 for testing
    'env': global_dbt_env
}

with DAG(
    'dbt_snowflake_pipeline',
    default_args=default_args,
    description='A DAG to run dbt models against Snowflake',
    schedule_interval=None, # Set to '@daily' when ready for production
    start_date=datetime(2026, 1, 1),
    catchup=False,
) as dag:

    # Task 1: Check the Snowflake connection and dbt project validity
    # dbt_debug = BashOperator(
    #     task_id='dbt_debug',
    #     bash_command=f'cd {DBT_PROJECT_DIR} && dbt debug --profiles-dir .'
    # )

    # Task 2: Install required dbt packages (if you use dbt_utils, etc.)
    dbt_deps = BashOperator(
        task_id='dbt_deps',
        bash_command=f'cd {DBT_PROJECT_DIR} && dbt deps --profiles-dir .'
    )

    # Task 3: Load seed data into Snowflake
    dbt_seed = BashOperator(
        task_id='dbt_seed',
        bash_command=f'cd {DBT_PROJECT_DIR} && dbt seed --profiles-dir .'
    )

    # Task 4: Execute the models
    dbt_run = BashOperator(
        task_id='dbt_run',
        bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --profiles-dir .'
    )
      

    # Task 5: Run your dbt tests
    dbt_test = BashOperator(
        task_id='dbt_test',
        bash_command=f'cd {DBT_PROJECT_DIR} && dbt test --profiles-dir .'
    )

    # Define the execution order
    # dbt_debug >> dbt_deps >> dbt_seed >> dbt_run >> dbt_test
    dbt_deps >> dbt_seed >> dbt_run >> dbt_test