# Use an official Python runtime as a parent image
FROM python:3.12-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
# Set the APP_ENV to production by default, can be overridden at runtime
ENV APP_ENV=production 

# Set the working directory in the container
WORKDIR /app

# Install system dependencies if needed (e.g., for packages with C extensions)
# RUN apt-get update && apt-get install -y --no-install-recommends gcc && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
# Copy requirements file from the source directory
COPY assiist_back_end/requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy only the necessary directories and files for the API server (exclude cloud_functions)
COPY assiist_back_end/api /app/assiist_back_end/api
COPY assiist_back_end/admin /app/assiist_back_end/admin
COPY assiist_back_end/containers.py /app/assiist_back_end/containers.py
COPY assiist_back_end/config.py /app/assiist_back_end/config.py
COPY assiist_back_end/db /app/assiist_back_end/db
COPY assiist_back_end/models /app/assiist_back_end/models
COPY assiist_back_end/services /app/assiist_back_end/services
COPY assiist_back_end/utils /app/assiist_back_end/utils
COPY assiist_back_end/schemas /app/assiist_back_end/schemas
COPY assiist_back_end/__init__.py /app/assiist_back_end/__init__.py

# Expose the port the app runs on (standard for Cloud Run is 8080)
EXPOSE 8080

# Define the command to run the API application using Uvicorn
# Use the absolute path as the code expects, relative to WORKDIR /app
CMD ["uvicorn", "assiist_back_end.api.main:app", "--host", "0.0.0.0", "--port", "8080"] 