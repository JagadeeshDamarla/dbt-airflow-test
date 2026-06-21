FROM apache/airflow:2.11.1

# Switch to root to install OS-level packages
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Switch back to the airflow user to install Python packages securely
USER airflow
RUN pip install --no-cache-dir "dbt-snowflake==1.8.3" "click==8.1.8"