FROM python:3.10-slim

# Set the working directory inside the container
WORKDIR /usr/app/dbt

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 1. FIX: Copy requirements.txt directly from the current context folder
# (If it's inside a 'dbt_models' folder right here, change this to: COPY dbt_models/requirements.txt .)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2. FIX: Copy all project files directly from the current context folder
COPY . .

# Set profile directory environment variable
ENV DBT_PROFILES_DIR=/usr/app/dbt

# Default command to run
CMD ["dbt", "build"]