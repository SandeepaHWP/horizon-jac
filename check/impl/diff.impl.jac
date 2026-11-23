impl wait_for(port: int) {
    for _ in range(200) {
        try {
            c = http.client.HTTPConnection("127.0.0.1", port, timeout=1.0);
            c.request("GET", "/healthz");
            c.getresponse().read();
            c.close();
            return;
        } except OSError {
            time.sleep(0.05);
        }
    }
    raise RuntimeError(f"nothing answers on {port}");
}

impl free(port: int) {
    try {
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=0.5);
        c.request("GET", "/healthz");
        c.getresponse().read();
        c.close();
    } except OSError {
        return;
    }
    raise RuntimeError(f"something already listens on {port}: stop it first");
}

impl running(r: Running) -> Running {
    for p in r.procs {
        if p.poll() is not None {
            raise RuntimeError(f"the {r.name} server ended as it started (status {p.returncode})");
        }
    }
    started_servers.append(r);
    return r;
}

impl start_original(env: dict[str, str], port: int) -> Running {
    free(port);
    data = tempfile.mkdtemp(prefix="orig-");
    full: dict[str, str] = dict(os.environ);
    full.update(env);
    full["PORT"] = str(port);
    full["HOST"] = "127.0.0.1";
    full["HORIZON_TELEMETRY_DB"] = os.path.join(data, "t.sqlite3");
    binary = os.environ.get("ORIGINAL", "");
    p = subprocess.Popen([binary], env=full, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL);
    wait_for(port);
    return running(Running(name="original", procs=[p], port=port, data=data));
}

impl start_port(env: dict[str, str], port: int) -> Running {
    free(port);
    free(port + 1);
    data = tempfile.mkdtemp(prefix="port-");
    dist = os.environ.get("PORT_DIST", "dist");
    full: dict[str, str] = dict(os.environ);
    full.update(env);
    full["JAC_DEPLOY_KEY"] = "diff-check-key";
    full["JAC_API_LISTEN"] = f"127.0.0.1:{port + 1}";
    full["JAC_REMOTE_API"] = f"http://127.0.0.1:{port + 1}";
    full["JAC_API_DATA"] = data;
    full["PORT"] = str(port);
    full["HOST"] = "127.0.0.1";
    full["JAC_TICKS_OFF"] = "all";
    api = subprocess.Popen([os.path.join(dist, "api-linux-x86_64")], env=full, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL);
    for _ in range(200) {
        try {
            c = http.client.HTTPConnection("127.0.0.1", port + 1, timeout=1.0);
            c.request("GET", "/");
            c.getresponse().read();
            c.close();
            break;
        } except OSError {
            time.sleep(0.05);
        }
    }
    gate = subprocess.Popen([os.path.join(dist, "gate-linux-x86_64")], env=full, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL);
    wait_for(port);
    return running(Running(name="port", procs=[gate, api], port=port, data=data));
}

impl stop(r: Running) {
    if r in started_servers {
        started_servers.remove(r);
    }
    for p in r.procs {
        p.terminate();
        p.wait();
    }
    shutil.rmtree(r.data, ignore_errors=True);
}

impl ask(port: int, method: str, path: str, headers: dict[str, str], body: bytes) -> Got {
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=30.0);
    c.request(method, path, body=body if body or method in ["POST", "PUT"] else None, headers=headers);
    resp = c.getresponse();
    raw = resp.read();
    kept: dict[str, str] = {};
    for (k, v) in resp.getheaders() {
        if k.lower() in COMPARED {
            kept[k.lower()] = v;
        }
    }
    c.close();
    return Got(status=resp.status, headers=kept, body=raw);
}

impl unordered(v: any) -> any {
    if isinstance(v, dict) {
        d: dict[str, any] = v;
        out: dict[str, any] = {k: unordered(x) for (k, x) in d.items()};
        for key in ["groups", "crashes_by_version"] {
            if key in out and isinstance(out[key], list) {
                listed: list[any] = out[key];
                out[key] = sorted(listed, key=lambda (x: any) -> str { json.dumps(x, sort_keys=True) });
            }
        }
        return out;
    }
    if isinstance(v, list) {
        items: list[any] = v;
        return [unordered(x) for x in items];
    }
    return v;
}

impl comparable(g: Got, loose: list[str]) -> any {
    raw = g.body;
    if g.headers.get("content-encoding", "") == "gzip" {
        raw = gzip.decompress(raw);
    }
    try {
        v: any = json.loads(raw.decode("utf-8"));
        if isinstance(v, dict) {
            d: dict[str, any] = v;
            for k in loose {
                if k in d {
                    d[k] = "<loose>";
                }
            }
        }
        return unordered(v);
    } except (ValueError, UnicodeDecodeError) {
        return raw.decode("utf-8", errors="replace");
    }
}

impl both(a: Running, b: Running, method: str, path: str, headers: dict[str, str] = {}, body: bytes = b"", loose: list[str] = []) -> tuple[Got, Got] {
    x = ask(a.port, method, path, headers, body);
    y = ask(b.port, method, path, headers, body);
    tally.compared += 1;
    what = f"[{scenario}] {method} {path}";
    if x.status != y.status {
        tally.differences.append(f"{what}: status {x.status} != {y.status} ({x.body[:120]!r} | {y.body[:120]!r})");
    } elif x.headers != y.headers {
        tally.differences.append(f"{what}: headers {x.headers} != {y.headers}");
    } elif comparable(x, loose) != comparable(y, loose) {
        tally.differences.append(f"{what}: body\n    original: {x.body[:600]!r}\n    port:     {y.body[:600]!r}");
    }
    return (x, y);
}

impl begin(name: str) {
    finish();
    scenario = name;
    scenario_start = (tally.compared, len(tally.differences));
}

impl finish {
    if scenario != "" {
        tally.per_scenario.append(
            (scenario, tally.compared - scenario_start[0], len(tally.differences) - scenario_start[1])
        );
        scenario = "";
    }
}

impl perf(gpu: str, distance: int) -> Item {
    t = Timings();
    for i in range(30000) {
        t.record(f32(8.0) + f32(i % 50) / f32(10.0));
    }
    return Item(
        day=u32(20741),
        source=Source.GAME,
        version="v2026.10.15",
        kind=Kind.PERF,
        perf=Perf(
            system=System(
                os="linux",
                os_version="Fedora Linux 43",
                cpu="AMD Ryzen 9 7950X",
                threads=u16(32),
                ram_gb=u16(32),
                gpu=gpu,
                driver="570.86",
                backend="Vulkan"
            ),
            settings=Settings(render_distance=u8(distance), simulation_distance=u8(12), graphics="fancy"),
            seconds=u32(1800),
            frames=t.summary(),
            peak_ram_mb=u32(2300)
        )
    );
}

impl batch(n: int, items: list[Item]) -> bytes {
    return encode_batch(Batch(schema=u32(1), install_id=f"{n:032x}", items=items));
}

impl post(a: Running, b: Running, n: int, items: list[Item], headers: dict[str, str] = {}) {
    h = {"content-encoding": "zstd"};
    h.update(headers);
    both(a, b, "POST", "/v1/batch", h, batch(n, items));
}

impl base_env -> dict[str, str] {
    return {
        "HORIZON_TELEMETRY_REQUESTS_PER_HOUR": "100000",
        "HORIZON_TELEMETRY_OFFICIAL_SERVER": "off",
        "HORIZON_TELEMETRY_GITHUB_TOKEN": "",
        "HORIZON_TELEMETRY_EXPORT_TOKEN": "",
        "TELEMETRY_EXPORT_TOKEN": ""
    };
}

impl run_all {
    glob_port = 8281;
    def pair(extra: dict[str, str]) -> tuple[Running, Running] {
        env = base_env();
        env.update(extra);
        return (start_original(env, glob_port), start_port(env, glob_port + 10));
    }
    def done(servers: tuple[Running, Running]) {
        stop(servers[0]);
        stop(servers[1]);
    }

    begin("totals show only groups with enough installs");
    s = pair({});
    for n in range(6) {
        post(s[0], s[1], n, [perf("NVIDIA GeForce RTX 4070", 12)] * 2);
    }
    for n in range(10, 12) {
        post(s[0], s[1], n, [perf("Intel(R) Arc A770", 8)]);
    }
    both(s[0], s[1], "GET", "/v1/aggregate?days=30");
    done(s);

    begin("totals break down by hardware class");
    s = pair({"HORIZON_TELEMETRY_MIN_INSTALL_DAYS": "1"});
    for n in range(4) {
        it = perf("NVIDIA GeForce RTX 4080", 12);
        it.perf.system.ram_gb = u16(16 if n == 3 else 31);
        it.perf.system.vram_mb = u32(16376);
        it.perf.system.gpu_kind = "discrete";
        it.perf.system.storage = "hdd" if n == 3 else "nvme";
        post(s[0], s[1], n, [it]);
    }
    both(s[0], s[1], "GET", "/v1/aggregate?days=30");
    done(s);

    begin("slow frames show what froze with enough installs");
    s = pair({"HORIZON_TELEMETRY_MIN_INSTALL_DAYS": "2"});
    for (n, span, frames, frame_max, span_max) in [
        (0, "renderer/r_uploads", 3, 900.0, 300.0),
        (1, "renderer/r_uploads", 3, 400.0, 300.0),
        (2, "tick/tick_mobs", 1, 260.0, 200.0),
    ] {
        it = perf("NVIDIA GeForce RTX 4070", 12);
        it.perf.slow_frames = [SlowFrames(span=span, frames=u32(frames), frame_max_ms=f32(frame_max), span_max_ms=f32(span_max))];
        post(s[0], s[1], n, [it]);
    }
    post(s[0], s[1], 3, [perf("NVIDIA GeForce RTX 4070", 12)]);
    both(s[0], s[1], "GET", "/v1/aggregate?days=30");
    done(s);

    begin("bad batches are refused");
    s = pair({});
    good = batch(1, [perf("x", 8)]);
    both(s[0], s[1], "POST", "/v1/batch", {}, good);
    both(s[0], s[1], "POST", "/v1/batch", {"content-encoding": "zstd"}, b"garbage");
    both(s[0], s[1], "POST", "/v1/batch", {"content-encoding": "zstd"}, bytes(262145));
    both(s[0], s[1], "POST", "/v1/batch", {"content-encoding": "ZSTD"}, encode_batch(Batch(schema=u32(1), install_id="not-an-id", items=[perf("x", 8)])));
    both(s[0], s[1], "POST", "/v1/batch", {"content-encoding": "zstd"}, encode_batch(Batch(schema=u32(2), install_id="0" * 32, items=[perf("x", 8)])));
    both(s[0], s[1], "POST", "/v1/batch", {"content-encoding": "zstd"}, encode_batch(Batch(schema=u32(1), install_id="0" * 32, items=[])));
    both(s[0], s[1], "POST", "/v1/batch", {"content-encoding": "gzip"}, good);
    both(s[0], s[1], "POST", "/v1/batch", {"content-encoding": "zstd"}, good);
    done(s);

    begin("an address is rate limited");
    s = pair({
        "HORIZON_TELEMETRY_REQUESTS_PER_HOUR": "30",
        "HORIZON_TELEMETRY_TRUST_PROXY": "1",
        "HORIZON_TELEMETRY_CLIENT_IP_HEADER": "x-forwarded-for"
    });
    for n in range(3) {
        post(s[0], s[1], n, [perf("x", 8)], {"x-forwarded-for": "203.0.113.9"});
    }
    post(s[0], s[1], 9, [perf("x", 8)], {"x-forwarded-for": "203.0.113.9"});
    post(s[0], s[1], 9, [perf("x", 8)], {"x-forwarded-for": "198.51.100.7, 203.0.113.9"});
    post(s[0], s[1], 9, [perf("x", 8)], {"x-forwarded-for": "203.0.113.9", "x-real-ip": "198.51.100.42"});
    post(s[0], s[1], 9, [perf("x", 8)], {"x-forwarded-for": "203.0.113.9, 198.51.100.7"});
    for forwarded in ["2001:db8::1", "2001:db8::2", "2001:db8::3", "2001:db8::ffff:ffff", "2001:db8:1::1", "::ffff:198.51.100.7"] {
        post(s[0], s[1], 9, [perf("x", 8)], {"x-forwarded-for": forwarded});
    }
    done(s);

    begin("an install has a daily cap");
    s = pair({"HORIZON_TELEMETRY_ITEMS_PER_DAY": "3"});
    post(s[0], s[1], 1, [perf("x", 8)] * 2);
    post(s[0], s[1], 1, [perf("x", 8)] * 2);
    post(s[0], s[1], 1, [perf("x", 8)]);
    post(s[0], s[1], 1, [perf("x", 8)]);
    done(s);

    begin("deleting an install removes its rows and its share of the totals");
    s = pair({"HORIZON_TELEMETRY_MIN_INSTALL_DAYS": "1"});
    crash = Item(day=u32(20741), source=Source.GAME, version="v1", kind=Kind.CRASH, crash=Crash());
    post(s[0], s[1], 1, [perf("Apple M4 Pro", 12), crash]);
    post(s[0], s[1], 2, [perf("Apple M4 Pro", 12)]);
    both(s[0], s[1], "GET", "/v1/aggregate?days=30");
    both(s[0], s[1], "DELETE", f"/v1/installs/{1:032x}");
    both(s[0], s[1], "GET", "/v1/aggregate?days=30");
    both(s[0], s[1], "DELETE", "/v1/installs/nope");
    both(s[0], s[1], "DELETE", f"/v1/installs/{7:032x}");
    done(s);

    begin("the windows answered can be listed, and uncached totals have a budget");
    s = pair({"HORIZON_TELEMETRY_AGGREGATE_DAYS": "7,30", "HORIZON_TELEMETRY_AGGREGATE_BUILDS_PER_HOUR": "10"});
    both(s[0], s[1], "GET", "/v1/aggregate?days=7");
    both(s[0], s[1], "GET", "/v1/aggregate?days=7");
    both(s[0], s[1], "GET", "/v1/aggregate?days=8");
    both(s[0], s[1], "GET", "/v1/aggregate");
    done(s);

    begin("query strings are read as axum reads them");
    s = pair({});
    for q in ["days=", "days=abc", "days=-1", "days=99999999999", "days=0", "days=999", "days=7&days=8", "days=%37", "other=1"] {
        both(s[0], s[1], "GET", f"/v1/aggregate?{q}");
    }
    done(s);

    begin("the totals are rate limited per address");
    s = pair({"HORIZON_TELEMETRY_READS_PER_HOUR": "20"});
    for _ in range(3) {
        both(s[0], s[1], "GET", "/v1/aggregate?days=30");
        both(s[0], s[1], "GET", "/v1/benchmarks/summary", {}, b"", ["generated"]);
    }
    done(s);

    begin("live pings count, and bad ones are refused");
    s = pair({"HORIZON_TELEMETRY_LIVE_MAX_SESSIONS": "3"});
    def ping(n: int, version: str, lan: bool) -> bytes {
        return json.dumps({"session": f"{n:032x}", "version": version, "platform": "linux", "lan": lan}).encode();
    }
    both(s[0], s[1], "POST", "/v1/live", {"content-type": "application/json"}, ping(1, "0.2.0", False));
    both(s[0], s[1], "POST", "/v1/live", {}, ping(2, "0.2.0", True));
    both(s[0], s[1], "POST", "/v1/live", {}, ping(3, "dev 0.1.0", False));
    both(s[0], s[1], "POST", "/v1/live", {}, ping(4, "0.2.0", False));
    both(s[0], s[1], "POST", "/v1/live", {}, ping(1, "0.2.0", False));
    both(s[0], s[1], "GET", "/v1/live");
    for bad in [
        b'{"session":"ABC","version":"0.2.0","platform":"linux","lan":false}',
        b'{"session":"00000000000000000000000000000000","version":"<script>","platform":"linux","lan":false}',
        b'{"session":"00000000000000000000000000000000","version":"0.2.0","platform":"haiku","lan":false}',
        bytes(600),
    ] {
        both(s[0], s[1], "POST", "/v1/live", {}, bad);
    }
    for q in ["", "?range=7d", "?range=30d", "?range=all", "?range=1y", "?series=official", "?series=lan", "?range=all&series=official"] {
        both(s[0], s[1], "GET", f"/v1/live/history{q}", {}, b"", ["from", "to"]);
    }
    done(s);

    begin("the live count has its own rate limit");
    s = pair({"HORIZON_TELEMETRY_LIVE_PER_HOUR": "30"});
    for _ in range(4) {
        both(s[0], s[1], "GET", "/v1/live");
    }
    both(s[0], s[1], "GET", "/v1/aggregate?days=30");
    done(s);

    begin("votes count once per browser and can be taken back");
    s = pair({});
    a = "0b7c3c9e-3f0a-4d8e-9a39-4c1f5a6b7d21";
    b = "1b7c3c9e-3f0a-4d8e-9a39-4c1f5a6b7d21";
    for (item, voter, up) in [("smooth-frames", a, True), ("smooth-frames", a, True), ("smooth-frames", b, True), ("smooth-frames", a, False), ("v2", b, True)] {
        both(s[0], s[1], "POST", "/hub/vote", {"content-type": "application/json"}, json.dumps({"item": item, "voter": voter, "up": up}).encode());
    }
    both(s[0], s[1], "POST", "/hub/vote", {}, json.dumps({"item": "Bad Item", "voter": a}).encode());
    both(s[0], s[1], "POST", "/hub/vote", {}, b"not json");
    both(s[0], s[1], "POST", "/hub/vote", {}, json.dumps({"item": "x", "voter": a, "pad": "y" * 30000}).encode());
    both(s[0], s[1], "GET", "/hub/votes");
    both(s[0], s[1], "OPTIONS", "/hub/vote");
    both(s[0], s[1], "OPTIONS", "/hub/report");
    both(s[0], s[1], "POST", "/hub/report", {}, json.dumps({"title": "Water is black"}).encode());
    both(s[0], s[1], "POST", "/v1/report", {}, json.dumps({"category": "bug"}).encode());
    done(s);

    begin("the hub is rate limited per address");
    s = pair({"HORIZON_TELEMETRY_HUB_PER_HOUR": "20"});
    for _ in range(3) {
        both(s[0], s[1], "GET", "/hub/votes");
    }
    done(s);

    begin("the export is off without a token and refuses a wrong one");
    s = pair({});
    both(s[0], s[1], "GET", "/v1/export/benchmarks");
    both(s[0], s[1], "GET", "/v1/export/hardware");
    done(s);
    s = pair({"TELEMETRY_EXPORT_TOKEN": "s3cret-token", "HORIZON_TELEMETRY_REQUESTS_PER_HOUR": "20"});
    for auth in ["", "Bearer nope", "Bearer s3cret-token", "Bearer s3cret-token ", "bearer s3cret-token", "Bearer nope", "Bearer nope"] {
        h: dict[str, str] = {"authorization": auth} if auth != "" else {};
        both(s[0], s[1], "GET", "/v1/export/benchmarks", h);
    }
    both(s[0], s[1], "GET", "/v1/export/benchmarks", {"authorization": "Bearer s3cret-token"});
    done(s);

    begin("benchmark reports and machines come out raw and in pages");
    s = pair({"TELEMETRY_EXPORT_TOKEN": "s3cret-token"});
    token = {"authorization": "Bearer s3cret-token"};
    for n in range(5) {
        doc = {"format": "horizon-benchmark-report", "version": 1, "n": n, "z": [1.5, 2.0], "a": {"b": None}};
        it = Item(day=u32(1), source=Source.LAUNCHER, version=f"0.1.{n}", kind=Kind.BENCHMARK, benchmark=json.dumps(doc));
        post(s[0], s[1], n, [it]);
    }
    for n in range(3) {
        it = perf("NVIDIA GeForce RTX 4070", 12);
        it.perf.system.cores = u16(8 + n % 2);
        it.perf.system.storage = "nvme";
        post(s[0], s[1], 10 + n, [it, perf("Apple M4 Pro", 16)]);
    }
    for q in ["", "?limit=2", "?after=2&limit=2", "?after=4", "?limit=0", "?limit=9999", "?after=-3", "?after=x"] {
        both(s[0], s[1], "GET", f"/v1/export/benchmarks{q}", token);
    }
    for q in ["", "?limit=1", "?offset=1&limit=1", "?offset=5", "?days=0", "?days=1000"] {
        both(s[0], s[1], "GET", f"/v1/export/hardware{q}", token, b"", ["from_day", "to_day"]);
    }
    both(s[0], s[1], "GET", "/v1/export/hardware", {"authorization": "Bearer s3cret-token", "accept-encoding": "br, GZip;q=0.5"}, b"", ["from_day", "to_day"]);
    done(s);

    begin("benchmark uploads come back grouped and anonymous");
    s = pair({});
    with open("test/fixtures/benchmarks/items.jsonl") as f {
        for line in f {
            if line.strip() == "" {
                continue;
            }
            v: dict[str, any] = json.loads(line);
            name = v.get("install_id");
            if not isinstance(name, str) {
                continue;
            }
            key = u128(0);
            for ch in name.encode() {
                key = key *% u128(257) +% u128(ch);
            }
            it = Item(day=u32(1), source=Source.GAME, version=v["version"], kind=Kind.BENCHMARK, benchmark=json.dumps(v["data"]));
            both(s[0], s[1], "POST", "/v1/batch", {"content-encoding": "zstd"}, encode_batch(Batch(schema=u32(1), install_id=f"{key:032x}", items=[it])));
        }
    }
    both(s[0], s[1], "GET", "/v1/benchmarks/summary", {}, b"", ["generated"]);
    done(s);

    begin("what is not a route");
    s = pair({});
    for (method, path) in [
        ("GET", "/nope"),
        ("GET", "/v1/batch"),
        ("PUT", "/v1/live"),
        ("GET", "/v1/installs/abc"),
        ("POST", "/healthz"),
        ("GET", "/healthz"),
        ("HEAD", "/healthz"),
        ("GET", "/v1/report"),
        ("GET", "/hub/vote"),
        ("DELETE", "/v1/installs/"),
        ("GET", "/v1/aggregate/"),
    ] {
        both(s[0], s[1], method, path);
    }
    done(s);
    finish();
}
