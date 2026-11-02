from pydantic_settings import (
    BaseSettings,
    SettingsConfigDict,
)


class Settings(BaseSettings):
    database_url: str

    session_secret: str

    session_https_only: bool = False

    local_auth_enabled: bool = True

    # Browser cookie maximum lifetime.
    session_max_age_seconds: int = 28800

    # ASPEN idle-session timeout.
    session_idle_minutes: int = 120

    login_max_attempts: int = 5

    login_lock_minutes: int = 15

    model_config = SettingsConfigDict(
        env_prefix="VSR_",
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


settings = Settings()
