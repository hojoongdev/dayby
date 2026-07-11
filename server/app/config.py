"""Application settings, loaded from environment variables (12-factor)."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # MongoDB
    mongodb_uri: str = "mongodb://localhost:27017"
    db_name: str = "dayby"

    # Providers (swappable; "mock" needs no API keys)
    llm_provider: str = "mock"
    stt_provider: str = "mock"

    # Gemini (used when llm_provider == "gemini")
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"
    # Vertex AI Express mode: use a Vertex AI api key instead of an AI Studio key
    # (no GCP project / service account needed).
    google_genai_use_vertexai: bool = False

    # Auth
    jwt_secret: str = "change-me-in-production"

    # App
    app_env: str = "development"

    # CORS: comma-separated browser origins allowed to call the API
    # (the Flutter web client). "*" is fine for local dev; lock this down in prod.
    cors_allow_origins: str = "*"


settings = Settings()
