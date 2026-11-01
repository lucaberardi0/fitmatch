FROM python:3.11-slim

# System dependencies for curl_cffi and network TLS
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY . .

# Expose FastAPI port
EXPOSE 8000

# Run FastAPI with background sync scheduler
CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000"]
