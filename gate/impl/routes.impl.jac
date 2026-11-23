impl Limits.forget_idle {
    for b in [self.requests, self.live, self.reads, self.hub, self.hub_posts] {
        b.forget_idle();
    }
}

impl rate_key(ip: str) -> str {
    try {
        a = ipaddress.ip_address(ip);
        if isinstance(a, ipaddress.IPv6Address) {
            v6: ipaddress.IPv6Address = a;
            mapped = v6.ipv4_mapped;
            if mapped is not None {
                return str(mapped);
            }
            return str(ipaddress.IPv6Address(v6.packed[:8] + bytes(8)));
        }
        return str(a);
    } except ValueError {
        return "0.0.0.0";
    }
}

impl client(r: Request) -> str {
    name = cfg.client_ip_header;
    if cfg.trust_proxy and name is not None and name in r.headers {
        value = r.headers[name];
        last = value.rsplit(",", 1)[-1].strip();
        if value.isascii() and value.isprintable() {
            try {
                ipaddress.ip_address(last);
                return rate_key(last);
            } except ValueError {}
        }
    }
    return rate_key(r.peer if r.peer != "" else "0.0.0.0");
}

impl hashed(r: Request) -> str {
    return hashlib.blake2b(client(r).encode(), key=limits.hub_key, digest_size=8).hexdigest();
}

impl text(status: int, message: str) -> Answer {
    return Answer(
        status=status,
        headers=[("content-type", "text/plain; charset=utf-8")],
        body=message.encode(),
    );
}

impl json_answer(body: str, max_age: int) -> Answer {
    origin = cfg.allow_origin
        if cfg.allow_origin.isascii() and cfg.allow_origin.isprintable()
        else "*";
    return Answer(
        status=200,
        headers=[
            ("content-type", "application/json"),
            ("cache-control", f"public, max-age={max_age}"),
            ("access-control-allow-origin", origin),
        ],
        body=body.encode(),
    );
}

impl hub_answer(status: int, body: str) -> Answer {
    a = json_answer(body, 0);
    a.status = status;
    a.headers = [(k, "no-store" if k == "cache-control" else v) for (k, v) in a.headers];
    return a;
}

impl hub_refuse(status: int, message: str) -> Answer {
    return hub_answer(status, dumps({"error": message}));
}

impl preflight -> Answer {
    a = hub_answer(204, "null");
    a.body = b"";
    a.headers = [(k, v) for (k, v) in a.headers if k != "content-type"] + [
        ("access-control-allow-methods", "POST"),
        ("access-control-allow-headers", "content-type"),
        ("access-control-max-age", "86400"),
    ];
    return a;
}

impl query_of(r: Request) -> dict[str, str] {
    out: dict[str, str] = {};
    for (k, v) in urllib.parse.parse_qsl(r.query, keep_blank_values=True) {
        if k in out {
            raise ValueError(f"duplicate field `{k}`");
        }
        out[k] = v;
    }
    return out;
}

impl query_uint(q: dict[str, str], name: str, fallback: int, most: int) -> int {
    if name not in q {
        return fallback;
    }
    v = q[name];
    if v == "" {
        raise ValueError(f"{name}: cannot parse integer from empty string");
    }
    n = parse_uint(v, most);
    if n is None {
        digits = v[1:] if v.startswith("+") else v;
        if digits != "" and all(c in "0123456789" for c in digits) {
            raise ValueError(f"{name}: number too large to fit in target type");
        }
        raise ValueError(f"{name}: invalid digit found in string");
    }
    return n;
}

impl query_int(q: dict[str, str], name: str, fallback: int) -> int {
    if name not in q {
        return fallback;
    }
    v = q[name];
    if v.startswith("-") {
        if v[1:].startswith("+") {
            raise ValueError(f"{name}: invalid digit found in string");
        }
        if v == "-9223372036854775808" {
            return -9223372036854775807 - 1;
        }
        try {
            return -query_uint({name: v[1:]}, name, 0, 9223372036854775807);
        } except ValueError as e {
            if "too large" in str(e) {
                raise ValueError(f"{name}: number too small to fit in target type");
            }
            raise e;
        }
    }
    return query_uint(q, name, fallback, 9223372036854775807);
}

impl query_refusal(e: ValueError) -> Answer {
    return text(400, f"Failed to deserialize query string: {e}");
}

impl same(sent: bytes, token: bytes) -> bool {
    diff = len(sent) ^ len(token);
    for (i, t) in enumerate(token) {
        diff |= (sent[i] if i < len(sent) else 0) ^ t;
    }
    return diff == 0;
}

impl export_refusal(r: Request) -> Answer | None {
    token = cfg.export_token;
    if token is None {
        return Answer(status=404);
    }
    auth = r.headers.get("authorization", "");
    sent = auth[len("Bearer "):] if auth.startswith("Bearer ") and auth.isascii() else "";
    if same(sent.encode(), token.encode()) {
        return None;
    }
    if not limits.requests.take(cfg.requests_per_hour, client(r)) {
        return text(429, "too many requests");
    }
    return Answer(status=401);
}

impl export_answer(r: Request, body: str) -> Answer {
    accepts = r.headers.get("accept-encoding", "");
    gz = any(c.strip().split(";")[0].strip().lower() == "gzip" for c in accepts.split(","));
    headers = [
        ("content-type", "application/json"),
        ("cache-control", "no-store"),
        ("vary", "Accept-Encoding"),
    ];
    raw = body.encode();
    if gz {
        return Answer(
            status=200,
            headers=[("content-encoding", "gzip")] + headers,
            body=gzip.compress(raw, mtime=0),
        );
    }
    return Answer(status=200, headers=headers, body=raw);
}

impl hub_body(r: Request, most: int) -> any {
    if r.body_over or len(r.body) > most {
        return hub_refuse(400, "too large");
    }
    try {
        return json.loads(r.body.decode("utf-8"));
    } except (ValueError, UnicodeDecodeError) {
        return hub_refuse(400, "send JSON");
    }
}

impl take_report_route(r: Request, kind: str, most: int, per_day: int) -> Answer {
    if cfg.github_token is None {
        return hub_refuse(503, "reports are closed here: use GitHub or Discord");
    }
    if not limits.hub_posts.take(cfg.hub_posts_per_hour, hashed(r)) {
        return hub_refuse(429, "too many requests");
    }
    body = hub_body(r, most);
    if isinstance(body, Answer) {
        return body;
    }
    bot = body.get("website") if isinstance(body, dict) else None;
    if isinstance(bot, str) and bot != "" {
        return hub_answer(202, dumps({"id": 0}));
    }
    fields: dict[str, any] = {};
    try {
        fields = game_fields(body) if kind == "game" else website_fields(body);
    } except ValueError as e {
        return hub_refuse(400, str(e));
    }
    reply: Reply = take_report(kind, fields_json(fields), per_day);
    return hub_answer(reply.status, reply.body);
}

impl answer_to(r: Request) -> Answer {
    routes: dict[str, list[str]] = {
        "/v1/batch": ["POST"],
        "/v1/live": ["POST", "GET", "HEAD"],
        "/v1/live/history": ["GET", "HEAD"],
        "/v1/aggregate": ["GET", "HEAD"],
        "/v1/benchmarks/summary": ["GET", "HEAD"],
        "/v1/export/benchmarks": ["GET", "HEAD"],
        "/v1/export/hardware": ["GET", "HEAD"],
        "/hub/vote": ["POST", "OPTIONS"],
        "/hub/votes": ["GET", "HEAD"],
        "/hub/report": ["POST", "OPTIONS"],
        "/v1/report": ["POST"],
        "/healthz": ["GET", "HEAD"],
    };
    path = urllib.parse.unquote(r.path);
    method = "GET" if r.method == "HEAD" else r.method;
    install_id: str | None = None;
    if path.startswith("/v1/installs/")
        and "/" not in path[len("/v1/installs/"):]
        and len(path) > len("/v1/installs/")
    {
        install_id = path[len("/v1/installs/"):];
        if r.method != "DELETE" {
            return Answer(status=405, headers=[("allow", "DELETE")]);
        }
    } elif path not in routes {
        return Answer(status=404);
    } elif r.method not in routes[path] {
        return Answer(status=405, headers=[("allow", ",".join(routes[path]))]);
    }
    try {
        if install_id is not None {
            if not limits.requests.take(cfg.requests_per_hour, client(r)) {
                return text(429, "too many requests");
            }
            if not is_install_id(install_id) {
                return text(400, "not an install ID");
            }
            forget_install(install_id);
            return Answer(status=204);
        }
        if path == "/healthz" {
            return text(200, "ok");
        }
        if path == "/v1/batch" {
            if not limits.requests.take(cfg.requests_per_hour, client(r)) {
                return text(429, "too many requests");
            }
            if r.headers.get("content-encoding", "").lower() != "zstd" {
                return text(415, "send zstd (Content-Encoding: zstd)");
            }
            if r.body_over or len(r.body) > MAX_COMPRESSED {
                return text(413, "a batch is at most 256 KiB");
            }
            b: Batch | None = None;
            try {
                b = decode_batch(r.body);
            } except ValueError as e {
                return text(400, str(e));
            }
            stored = take_batch(batch_json(b));
            if stored == 429 {
                return text(429, "this install's daily limit is reached");
            }
            if stored == 503 {
                return text(503, "try again later");
            }
            return Answer(status=204);
        }
        if path == "/v1/aggregate" {
            if not limits.reads.take(cfg.reads_per_hour, client(r)) {
                return text(429, "too many requests");
            }
            asked = 30;
            try {
                asked = query_uint(query_of(r), "days", 30, 4294967295);
            } except ValueError as e {
                return query_refusal(e);
            }
            allowed = cfg.aggregate_days;
            days = asked;
            if allowed is not None {
                if asked not in allowed {
                    return text(400, "days: one of " + ", ".join(str(d) for d in allowed));
                }
            } else {
                days = min(max(asked, 1), 366);
            }
            made = totals(days);
            if made == "" {
                return text(503, "try again in a minute");
            }
            return json_answer(made, 600);
        }
        if path == "/v1/benchmarks/summary" {
            if not limits.reads.take(cfg.reads_per_hour, client(r)) {
                return text(429, "too many requests");
            }
            return json_answer(bench_summary(), 600);
        }
        if path == "/v1/export/benchmarks" or path == "/v1/export/hardware" {
            q: dict[str, str] = {};
            try {
                q = query_of(r);
            } except ValueError as e {
                return query_refusal(e);
            }
            refused = export_refusal(r);
            if refused is not None {
                return refused;
            }
            try {
                if path == "/v1/export/benchmarks" {
                    limit = min(max(query_uint(q, "limit", 100, 4294967295), 1), 500);
                    after = query_int(q, "after", 0);
                    return export_answer(r, export_reports(after, limit));
                }
                days = min(max(query_uint(q, "days", 30, 4294967295), 1), 366);
                offset = query_uint(q, "offset", 0, 9223372036854775807);
                limit = min(max(query_uint(q, "limit", 200, 9223372036854775807), 1), 1000);
                return export_answer(r, export_hardware(days, offset, limit));
            } except ValueError as e {
                return query_refusal(e);
            }
        }
        if path == "/v1/live" and method == "POST" {
            if not limits.live.take(cfg.live_per_hour, client(r)) {
                return text(429, "too many requests");
            }
            if r.body_over or len(r.body) > MAX_PING_BYTES {
                return text(413, "a ping is at most 512 bytes");
            }
            p: Ping | None = None;
            try {
                p = ping_of(r.body);
            } except ValueError as e {
                return text(400, str(e));
            }
            why = ping_check(p);
            if why is not None {
                return text(400, why);
            }
            if not take_ping(p) {
                return text(503, "try again later");
            }
            return Answer(status=204);
        }
        if path == "/v1/live" {
            if not limits.live.take(cfg.live_per_hour, client(r)) {
                return text(429, "too many requests");
            }
            return json_answer(live_now(), cfg.live_window // 8);
        }
        if path == "/v1/live/history" {
            if not limits.live.take(cfg.live_per_hour, client(r)) {
                return text(429, "too many requests");
            }
            q: dict[str, str] = {};
            try {
                q = query_of(r);
            } except ValueError as e {
                return query_refusal(e);
            }
            range_name = q.get("range", "24h");
            series = q.get("series", "players");
            if range_name not in ["24h", "7d", "30d", "all"] {
                return text(400, "range: 24h, 7d, 30d or all");
            }
            if series not in ["players", "official"] {
                return text(400, "series: players or official");
            }
            made = history(series, range_name);
            if made == "" {
                return text(503, "try again later");
            }
            return json_answer(made, 60);
        }
        if r.method == "OPTIONS" {
            return preflight();
        }
        if path == "/hub/vote" {
            if not limits.hub.take(cfg.hub_per_hour, hashed(r)) {
                return hub_refuse(429, "too many requests");
            }
            body = hub_body(r, HUB_MAX_BODY);
            if isinstance(body, Answer) {
                return body;
            }
            item = body.get("item") if isinstance(body, dict) else None;
            voter = body.get("voter") if isinstance(body, dict) else None;
            item_text = item if isinstance(item, str) else "";
            voter_text = voter if isinstance(voter, str) else "";
            if not item_id(item_text) or not voter_id(voter_text) {
                return hub_refuse(400, "an item id and a voter id");
            }
            up_value = body.get("up") if isinstance(body, dict) else None;
            up = up_value if isinstance(up_value, bool) else True;
            counted = take_vote(item_text, voter_text, up);
            if counted is None {
                return hub_refuse(400, "no such item");
            }
            return hub_answer(200, dumps({"item": item_text, "votes": counted}));
        }
        if path == "/hub/votes" {
            if not limits.hub.take(cfg.hub_per_hour, hashed(r)) {
                return hub_refuse(429, "too many requests");
            }
            return json_answer(vote_counts(), 60);
        }
        if path == "/hub/report" {
            return take_report_route(r, "report", HUB_MAX_BODY, cfg.hub_reports_per_day);
        }
        if path == "/v1/report" {
            return take_report_route(r, "game", GAME_MAX_BODY, cfg.game_reports_per_day);
        }
    } except RemoteError as e {
        print(f"horizon-telemetry-server: the api did not answer: {e}", file=sys.stderr);
        return text(503, "try again later");
    }
    return Answer(status=404);
}
