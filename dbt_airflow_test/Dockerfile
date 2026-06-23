FROM python:3.10-slim

# Set the working directory inside the container
WORKDIR /usr/app/dbt

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy requirements from your nested subfolder
COPY dbt_models/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy only the nested dbt project contents into the working directory
COPY dbt_airflow_test/ .

# Point to where profiles.yml lives inside the container
ENV DBT_PROFILES_DIR=/usr/app/dbt

# Default command for the Cloud Run Job
CMD ["dbt", "build"]