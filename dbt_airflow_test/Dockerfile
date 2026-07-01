FROM python:3.10-slim

# Set the working directory inside the container
WORKDIR /usr/app/dbt

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 1. FIX: Copy requirements.txt directly from the current context folder
# (If it's inside a 'dbt_models' folder right here, change this to: COPY dbt_models/requirements.txt .)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2. FIX: Copy all project files directly from the current context folder
COPY . .

# Ensure the runtime wrapper is executable
RUN chmod +x /usr/app/dbt/run_dbt_with_log_upload.sh

# Set profile directory environment variable
ENV DBT_PROFILES_DIR=/usr/app/dbt

# Default command to run (always uploads logs to GCS after dbt exits)
CMD ["/usr/app/dbt/run_dbt_with_log_upload.sh"]