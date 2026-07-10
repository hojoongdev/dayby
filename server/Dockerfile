FROM python:3.12-slim

WORKDIR /app

# uv: fast, reproducible Python dependency management.
RUN pip install --no-cache-dir uv

# Install dependencies first for better layer caching.
COPY pyproject.toml ./
RUN uv pip install --system --no-cache -r pyproject.toml

# App code (also bind-mounted in docker-compose for live reload).
COPY app ./app

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
