"""Application settings, loaded from environment variables (12-factor)."""
from pydantic_settings import BaseSettings, SettingsConfigDict

# The out-of-the-box secret. Fine for local development, never for a deployment that signs
# real sessions -- anyone who reads this file could forge a token signed with it.
DEFAULT_JWT_SECRET = "change-me-in-production"

# Every placeholder that ships in the repo: this default and the one docker-compose.yml
# falls back to. None may sign real sessions, so a deployment must set its own.
PLACEHOLDER_JWT_SECRETS = frozenset(
    {DEFAULT_JWT_SECRET, "dev-secret-not-for-production-generate-a-real-one"}
)


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
    # How long to wait on one Gemini call. The slowest real one is a grounded answer over
    # a busy week, at around twenty seconds. With no limit, a dropped connection is
    # retried out of sight for minutes and the caller holds a request that never returns.
    gemini_timeout_ms: int = 45_000

    # Auth. "none" = no identity provider; the caller names its family with the
    # X-Family-Id header, which is only allowed in development. "mock" runs the whole
    # sign-in flow with no keys (development only). "google" verifies real ID tokens.
    auth_provider: str = "none"
    google_client_id: str = ""
    jwt_secret: str = DEFAULT_JWT_SECRET
    access_token_ttl_minutes: int = 30
    refresh_token_ttl_days: int = 60

    # How long a family invite code stays good. Long enough to text a partner and have
    # them join later; short enough that a leaked code does not open the family forever.
    invite_ttl_hours: int = 168  # 7 days

    # How often one caller may hit the Gemini-backed ingest endpoints. Well above any human
    # rate; it exists to cap an abused endpoint, where each call is two model calls.
    ingest_rate_per_minute: int = 30

    # App
    app_env: str = "development"

    @property
    def auth_enabled(self) -> bool:
        return self.auth_provider != "none"

    @property
    def is_development(self) -> bool:
        return self.app_env == "development"

    @property
    def jwt_secret_is_placeholder(self) -> bool:
        return self.jwt_secret in PLACEHOLDER_JWT_SECRETS

    # CORS: comma-separated browser origins allowed to call the API
    # (the Flutter web client). "*" is fine for local dev; lock this down in prod.
    cors_allow_origins: str = "*"


settings = Settings()
