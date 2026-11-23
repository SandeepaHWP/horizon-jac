impl today -> int {
    return unix_now() // 86400 + day_shift;
}

impl unix_now -> int {
    return int(time.time());
}

impl utc_stamp -> str {
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime());
}

impl ready {
    if not requeued {
        requeue_filing();
        requeued = True;
    }
}

impl forget_cached {
    caches.totals.clear();
    caches.summary = None;
}

impl take_batch(batch: str) -> int {
    b = batch_of(json.loads(batch));
    with data_lock {
        ready();
        day = today();
        if count_on(b.install_id, day) + len(b.items) > cfg.items_per_day {
            return 429;
        }
        try {
            insert(b, day);
        } except Exception as e {
            print(f"horizon-telemetry-server: could not store a batch: {e}", file=sys.stderr);
            return 503;
        }
    }
    return 204;
}

impl forget_install(key: str) -> int {
    deleted = 0;
    with data_lock {
        deleted = delete_install(key);
    }
    if deleted > 0 {
        forget_cached();
    }
    return deleted;
}

impl totals(days: int) -> str {
    now = time.monotonic();
    hit = caches.totals.get(days);
    if hit is not None and now - hit[0] < CACHE_FOR {
        return hit[1];
    }
    if not builds.take(cfg.aggregate_builds_per_hour, "all") {
        return "";
    }
    text = "";
    with data_lock {
        end = today();
        text = aggregate(end + 1 - min(days, end + 1), end, cfg.min_install_days);
    }
    caches.totals[days] = (time.monotonic(), text);
    return text;
}

impl bench_summary -> str {
    hit = caches.summary;
    if hit is not None and time.monotonic() - hit[0] < CACHE_FOR {
        return hit[1];
    }
    text = "";
    with data_lock {
        uploads = benchmark_uploads(max(today() - cfg.retention_days, 0));
        text = summary(uploads, MIN_INSTALLS, utc_stamp());
    }
    caches.summary = (time.monotonic(), text);
    return text;
}

impl export_reports(after: int, limit: int) -> str {
    found: list[dict[str, any]] = [];
    with data_lock {
        found = export_benchmarks(after, limit);
    }
    next_id: any = found[-1]["id"] if found and len(found) == limit else None;
    return dumps({"reports": found, "next": next_id});
}

impl export_hardware(days: int, offset: int, limit: int) -> str {
    every: list[dict[str, any]] = [];
    end = today();
    start = end + 1 - min(days, end + 1);
    with data_lock {
        every = export_machines(start, end);
    }
    page = every[offset:offset + limit];
    following: any = offset + len(page) if offset + len(page) < len(every) else None;
    return dumps({
        "from_day": start,
        "to_day": end,
        "total_machines": len(every),
        "bucket_edges_ms": [tenth(float(f32(e))) for e in BUCKET_EDGES_MS],
        "machines": page,
        "next_offset": following,
    });
}

impl take_ping(p: Ping) -> bool {
    with data_lock {
        return live_ping(p, time.monotonic(), cfg.live_window, cfg.live_max_sessions);
    }
}

impl live_now -> str {
    fresh_for = float(cfg.live_window) / 8.0;
    hit = caches.live;
    if hit is not None and time.monotonic() - hit[0] < fresh_for {
        return hit[1];
    }
    text = "";
    with data_lock {
        text = count_json(live_count(time.monotonic(), cfg.live_window));
    }
    caches.live = (time.monotonic(), text);
    return text;
}

impl history(series: str, range_name: str) -> str {
    key = f"{series} {range_name}";
    hit = caches.history.get(key);
    if hit is not None and time.monotonic() - hit[0] < HISTORY_FOR {
        return hit[1];
    }
    text: str | None = None;
    with data_lock {
        text = live_history(series, range_name, unix_now());
    }
    if text is None {
        return "";
    }
    caches.history[key] = (time.monotonic(), text);
    return text;
}

impl take_vote(item: str, voter: str, up: bool) -> int | None {
    counted: int | None = None;
    with data_lock {
        counted = vote(item, voter, up);
    }
    if counted is not None {
        caches.votes = None;
    }
    return counted;
}

impl vote_counts -> str {
    hit = caches.votes;
    if hit is not None and time.monotonic() - hit[0] < VOTES_FOR {
        return hit[1];
    }
    text = "";
    with data_lock {
        text = votes_json();
    }
    caches.votes = (time.monotonic(), text);
    return text;
}

impl issue_for(kind: str, fields: dict[str, any]) -> Issue {
    return game_issue(fields) if kind == KIND else website_issue(fields);
}

impl take_report(kind: str, fields: str, per_day: int) -> Reply {
    day = today();
    id = 0;
    issue: str | None = None;
    with data_lock {
        ready();
        if queued_on(kind, day) >= per_day {
            return Reply(
                status=503, body=dumps({"error": "too many today: please try again tomorrow"})
            );
        }
        (id, issue) = enqueue(kind, day, max(day - 1, 0), fields);
    }
    if issue is not None {
        return Reply(status=201, body=dumps({"id": id, "issue": issue}));
    }
    claimed = False;
    with data_lock {
        claimed = claim(id);
    }
    if not claimed {
        return Reply(status=202, body=dumps({"id": id, "issue": None}));
    }
    token = cfg.github_token or "";
    try {
        url = open_issue(
            cfg.github_api, cfg.github_repo, token, issue_for(kind, json.loads(fields))
        );
        with data_lock {
            filed(id, url);
        }
        return Reply(status=201, body=dumps({"id": id, "issue": url}));
    } except RuntimeError as e {
        print(f"horizon-telemetry-server: report {id} not opened yet: {e}", file=sys.stderr);
        with data_lock {
            release_claim(id);
        }
        return Reply(status=202, body=dumps({"id": id, "issue": None}));
    }
}

impl install_newest(key: str) -> int | None {
    with data_lock {
        return newest_day(key);
    }
}

impl maintain -> int {
    removed = 0;
    with data_lock {
        ready();
        day = today();
        removed = expire(max(day - cfg.retention_days, 0));
        expire_queue(max(day - cfg.hub_keep_days, 0), max(day - RETRY_DAYS, 0));
        live_forget(time.monotonic(), cfg.live_window);
        prune_live(unix_now(), cfg.live_minute_days, max(cfg.live_hour_days, 31));
    }
    if removed > 0 {
        forget_cached();
    }
    return removed;
}

impl file_pending {
    if cfg.github_token is None {
        return;
    }
    pending: list[tuple[int, str, str]] = [];
    with data_lock {
        pending = [(q.id, q.kind, q.body) for q in unfiled(max(today() - RETRY_DAYS, 0))];
    }
    for (id, kind, body) in pending {
        claimed = False;
        with data_lock {
            claimed = claim(id);
        }
        if not claimed {
            continue;
        }
        try {
            url = open_issue(
                cfg.github_api,
                cfg.github_repo,
                cfg.github_token or "",
                issue_for(kind, json.loads(body)),
            );
            with data_lock {
                filed(id, url);
            }
        } except RuntimeError as e {
            print(f"horizon-telemetry-server: report {id} still not opened: {e}", file=sys.stderr);
            with data_lock {
                release_claim(id);
            }
            return;
        }
    }
}

impl record_players -> bool {
    if time.monotonic() - started < float(cfg.live_window) {
        return False;
    }
    with data_lock {
        c = live_count(time.monotonic(), cfg.live_window);
        return record_live("players", unix_now(), sample_of(c));
    }
}

impl record_official -> bool {
    address = cfg.official_server;
    if address is None {
        return False;
    }
    unix = unix_now();
    online = 0;
    try {
        online = players(address, 5.0).online;
    } except Exception {
        return False;
    }
    if online > MAX_OFFICIAL_PLAYERS {
        return False;
    }
    with data_lock {
        return record_live("official", unix, Sample(playing=online));
    }
}

impl upkeep {
    try {
        maintain();
    } except Exception as e {
        print(f"horizon-telemetry-server: upkeep failed: {e}", file=sys.stderr);
    }
    def filing {
        file_pending();
        commit();
    }
    threading.Thread(target=filing).start();
}

impl every_minute {
    try {
        record_players();
    } except Exception as e {
        print(f"horizon-telemetry-server: could not record the live count: {e}", file=sys.stderr);
    }
    def official {
        try {
            record_official();
            commit();
        } except Exception as e {
            print(
                f"horizon-telemetry-server: could not record the official server: {e}",
                file=sys.stderr,
            );
        }
    }
    threading.Thread(target=official).start();
}
