"""The server's settings, all from environment variables, with the original's defaults. Both the
gate and the api read them: each program starts with the same environment."""
import os;

"""The website: the browser origin answered by default, and where a game report's capture link
must point."""
glob WEBSITE: str = "https://playhorizon.dev";

obj Config {
    has retention_days: int = 180,
        min_install_days: int = 5,
        requests_per_hour: float = 60.0,
        items_per_day: int = 100,
        trust_proxy: bool = False,
        client_ip_header: str | None = None,
        allow_origin: str = "https://playhorizon.dev",
        live_per_hour: float = 600.0,
        live_window: int = 120,
        live_max_sessions: int = 200000,
        live_minute_days: int = 7,
        live_hour_days: int = 90,
        official_server: str | None = "play.playhorizon.dev:24454",
        hub_per_hour: float = 600.0,
        hub_posts_per_hour: float = 20.0,
        hub_reports_per_day: int = 30,
        game_reports_per_day: int = 20,
        hub_keep_days: int = 90,
        export_token: str | None = None,
        github_token: str | None = None,
        github_repo: str = "horizon-rust/horizon",
        reads_per_hour: float = 600.0,
        aggregate_builds_per_hour: float = 600.0,
        aggregate_days: list[int] | None = None,
        github_api: str = "https://api.github.com";

    """Why the client-address settings can't run, when they can't."""
    def client_ip_refusal -> str | None;

    """What the client-address settings will do, when it isn't what they seem to ask for."""
    def client_ip_warning -> str | None;
}

"""The defaults, with every `HORIZON_TELEMETRY_*` variable that is set and parses."""
def config_from_env -> Config;

"""`7,30,90,366` as the `days` `/v1/aggregate` answers: None when empty or when any value isn't a
number from 1 to 366."""
def parse_days(text: str) -> list[int] | None;

"""A header name as given, lowercase; None when empty or not a header name."""
def header_name(text: str) -> str | None;

"""Rust's `str::parse::<u64>`: digits, an optional `+`, nothing else."""
def parse_uint(text: str, most: int) -> int | None;

"""Rust's `str::parse::<f64>`: no spaces and no underscores, as Python's `float` allows."""
def parse_float(text: str) -> float | None;
