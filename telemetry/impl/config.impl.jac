impl parse_uint(text: str, most: int) -> int | None {
    t = text[1:] if text.startswith("+") else text;
    if t == "" or not all(c in "0123456789" for c in t) {
        return None;
    }
    if len(t.lstrip("0")) > 19 {
        return None;
    }
    try {
        n = int(t);
        return n if n <= most else None;
    } except OverflowError {
        return None;
    }
}

impl parse_float(text: str) -> float | None {
    t = text;
    if t[:1] in ["+", "-"] {
        t = t[1:];
    }
    if t.lower() in ["inf", "infinity", "nan"] {
        return float(text);
    }
    seen_digit = False;
    for c in t {
        if c in "0123456789" {
            seen_digit = True;
        } elif c not in ".eE+-" {
            return None;
        }
    }
    if not seen_digit {
        return None;
    }
    try {
        return float(text);
    } except ValueError {
        return None;
    }
}

impl parse_days(text: str) -> list[int] | None {
    days: list[int] = [];
    for part in text.split(",") {
        d = part.strip();
        if d == "" {
            continue;
        }
        n = parse_uint(d, 4294967295);
        if n is None or n < 1 or n > 366 {
            return None;
        }
        days.append(n);
    }
    return days or None;
}

impl header_name(text: str) -> str | None {
    name = text.strip().lower();
    tchar = "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyz";
    if name == "" or not all(c in tchar for c in name) {
        return None;
    }
    return name;
}

impl config_from_env -> Config {
    d = Config();
    def var(k: str) -> str | None {
        return os.environ.get(f"HORIZON_TELEMETRY_{k}");
    }
    def uint(k: str, fallback: int, most: int) -> int {
        v = var(k);
        n = parse_uint(v, most) if v is not None else None;
        return n if n is not None else fallback;
    }
    def real(k: str, fallback: float) -> float {
        v = var(k);
        x = parse_float(v) if v is not None else None;
        return x if x is not None else fallback;
    }
    def secret(k: str) -> str | None {
        v = var(k);
        if v is None or v.strip() == "" {
            return None;
        }
        return v.strip();
    }
    u32_max = 4294967295;
    official = d.official_server;
    o = var("OFFICIAL_SERVER");
    if o is not None {
        official = None if o.strip() in ["", "off"] else o.strip();
    }
    export = os.environ.get("TELEMETRY_EXPORT_TOKEN");
    export_token = export.strip()
        if export is not None and export.strip() != ""
        else secret("EXPORT_TOKEN");
    header = var("CLIENT_IP_HEADER");
    days = var("AGGREGATE_DAYS");
    trust = var("TRUST_PROXY");
    return Config(
        retention_days=uint("RETENTION_DAYS", d.retention_days, u32_max),
        min_install_days=uint("MIN_INSTALL_DAYS", d.min_install_days, 9223372036854775807),
        requests_per_hour=real("REQUESTS_PER_HOUR", d.requests_per_hour),
        items_per_day=uint("ITEMS_PER_DAY", d.items_per_day, u32_max),
        trust_proxy=trust is not None and trust == "1",
        client_ip_header=header_name(header) if header is not None else None,
        allow_origin=var("ALLOW_ORIGIN") or d.allow_origin
            if var("ALLOW_ORIGIN") is not None
            else d.allow_origin,
        live_per_hour=real("LIVE_PER_HOUR", d.live_per_hour),
        live_window=uint("LIVE_WINDOW_SECONDS", d.live_window, 9223372036854775807),
        live_max_sessions=uint("LIVE_MAX_SESSIONS", d.live_max_sessions, 9223372036854775807),
        live_minute_days=uint("LIVE_MINUTE_DAYS", d.live_minute_days, u32_max),
        live_hour_days=uint("LIVE_HOUR_DAYS", d.live_hour_days, u32_max),
        official_server=official,
        hub_per_hour=real("HUB_PER_HOUR", d.hub_per_hour),
        hub_posts_per_hour=real("HUB_POSTS_PER_HOUR", d.hub_posts_per_hour),
        hub_reports_per_day=uint("HUB_REPORTS_PER_DAY", d.hub_reports_per_day, u32_max),
        game_reports_per_day=uint("GAME_REPORTS_PER_DAY", d.game_reports_per_day, u32_max),
        hub_keep_days=uint("HUB_KEEP_DAYS", d.hub_keep_days, u32_max),
        export_token=export_token,
        github_token=secret("GITHUB_TOKEN"),
        github_repo=var("GITHUB_REPO") or d.github_repo
            if var("GITHUB_REPO") is not None
            else d.github_repo,
        reads_per_hour=real("READS_PER_HOUR", d.reads_per_hour),
        aggregate_builds_per_hour=real("AGGREGATE_BUILDS_PER_HOUR", d.aggregate_builds_per_hour),
        aggregate_days=parse_days(days) if days is not None else None,
        github_api=var("GITHUB_API") or d.github_api
            if var("GITHUB_API") is not None
            else d.github_api,
    );
}

impl Config.client_ip_refusal -> str | None {
    if self.trust_proxy and self.client_ip_header is None {
        return ("HORIZON_TELEMETRY_TRUST_PROXY=1 needs HORIZON_TELEMETRY_CLIENT_IP_HEADER, the header your "
            "proxy overwrites with the client's address (cf-connecting-ip behind Cloudflare, as the "
            "Dockerfile sets): without it every client would count as the proxy and share one "
            "rate-limit bucket. Not starting.");
    }
    return None;
}

impl Config.client_ip_warning -> str | None {
    if not self.trust_proxy and self.client_ip_header is not None {
        return (f"HORIZON_TELEMETRY_CLIENT_IP_HEADER={self.client_ip_header} is ignored without "
            "HORIZON_TELEMETRY_TRUST_PROXY=1: rate limits count the TCP peer");
    }
    return None;
}
