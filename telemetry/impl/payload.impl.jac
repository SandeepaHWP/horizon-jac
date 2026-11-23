impl kind_name(k: Kind) -> str {
    return k.name.lower();
}

impl kind_of(name: str) -> Kind | None {
    for k in Kind {
        if kind_name(k) == name {
            return k;
        }
    }
    return None;
}

impl max_bytes(k: Kind) -> int {
    return {Kind.PERF: 4096, Kind.CRASH: 32768, Kind.BUG: 81920, Kind.BENCHMARK: 131072}[k];
}

impl is_install_id(id: str) -> bool {
    return len(id) == 32 and all(c in "0123456789abcdef" for c in id);
}

impl decoded[T](v: any, at: str) -> T {
    try {
        return decode[T](v);
    } except CodecError as e {
        raise ValueError(f"{at}: {e}");
    } except OverflowError {
        raise ValueError(f"{at}: a number out of range");
    }
}

impl item_of(v: any) -> Item {
    if not isinstance(v, dict) {
        raise ValueError("an item is a JSON object");
    }
    o: dict[str, any] = v;
    for key in ["day", "source", "version", "kind", "data"] {
        if key not in o {
            raise ValueError(f"missing field `{key}`");
        }
    }
    source_name = decoded[str](o["source"], "source");
    source: Source | None = None;
    for s in Source {
        if s.name.lower() == source_name {
            source = s;
        }
    }
    if source is None {
        raise ValueError(f"unknown variant `{source_name}`, expected `launcher` or `game`");
    }
    kind_text = decoded[str](o["kind"], "kind");
    kind = kind_of(kind_text);
    if kind is None {
        raise ValueError(
            f"unknown variant `{kind_text}`, expected one of `perf`, `crash`, `bug`, `benchmark`"
        );
    }
    it = Item(
        day=decoded[u32](o["day"], "day"),
        source=source,
        version=decoded[str](o["version"], "version"),
        kind=kind,
    );
    data: any = o["data"];
    if kind == Kind.PERF {
        it.perf = decoded[Perf](data, "data");
    } elif kind == Kind.CRASH {
        it.crash = decoded[Crash](data, "data");
    } elif kind == Kind.BUG {
        it.bug = decoded[Bug](data, "data");
    } else {
        it.benchmark = value_json(data);
    }
    return it;
}

impl batch_of(v: any) -> Batch {
    if not isinstance(v, dict) {
        raise ValueError("a batch is a JSON object");
    }
    o: dict[str, any] = v;
    for key in ["schema", "install_id", "items"] {
        if key not in o {
            raise ValueError(f"missing field `{key}`");
        }
    }
    if not isinstance(o["items"], list) {
        raise ValueError("items: a list");
    }
    raw: list[any] = o["items"];
    return Batch(
        schema=decoded[u32](o["schema"], "schema"),
        install_id=decoded[str](o["install_id"], "install_id"),
        items=[item_of(x) for x in raw],
    );
}

impl validate(it: Item) -> str | None {
    size = len(item_json(it).encode());
    k = it.kind;
    if size > max_bytes(k) {
        return f"a {kind_name(k)} item of {size} bytes is over its {max_bytes(k)} bytes";
    }
    if len(it.version.encode()) > 64 {
        return "the version is too long";
    }
    if it.bug is not None {
        if it.bug.text.strip() == "" {
            return "a bug report needs text";
        }
        if len(it.bug.text) > BUG_MAX_TEXT {
            return f"a bug report is at most {BUG_MAX_TEXT} characters";
        }
    }
    if k == Kind.BENCHMARK and not it.benchmark.startswith("{") {
        return "a benchmark report is a JSON object";
    }
    if it.perf is not None {
        spans = it.perf.slow_frames;
        if len(spans) > SLOW_MAX_SPANS or any(len(s.span.encode()) > SLOW_MAX_NAME for s in spans) {
            return f"at most {SLOW_MAX_SPANS} slow-frame spans of {SLOW_MAX_NAME} bytes";
        }
    }
    return None;
}

impl value_json(v: any) -> str {
    return json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False);
}

impl jstr(s: str) -> str {
    return json.dumps(s, ensure_ascii=False);
}

impl f32_json(x: f32) -> str {
    text = str(x);
    if "e" not in text and "." not in text and "n" not in text {
        text += ".0";
    }
    return text;
}

impl display_json(d: Display) -> str {
    return f'{{"width":{d.width},"height":{d.height},"refresh_hz":{d.refresh_hz},"scale":{f32_json(d.scale)}}}';
}

impl system_json(s: System) -> str {
    shown = f',"display":{display_json(s.display)}' if s.display is not None else "";
    return (f'{{"os":{jstr(s.os)},"os_version":{jstr(s.os_version)},"arch":{jstr(s.arch)},'
        f'"cpu":{jstr(s.cpu)},"threads":{s.threads},"cores":{s.cores},'
        f'"cpu_base_mhz":{s.cpu_base_mhz},"cpu_boost_mhz":{s.cpu_boost_mhz},"ram_gb":{s.ram_gb},'
        f'"gpu":{jstr(s.gpu)},"gpu_vendor":{jstr(s.gpu_vendor)},"gpu_kind":{jstr(s.gpu_kind)},'
        f'"vram_mb":{s.vram_mb},"driver":{jstr(s.driver)},"backend":{jstr(s.backend)},'
        f'"storage":{jstr(s.storage)}{shown},"power":{jstr(s.power)},"form":{jstr(s.form)}}}');
}

impl settings_json(s: Settings) -> str {
    return (f'{{"render_distance":{s.render_distance},"simulation_distance":{s.simulation_distance},'
        f'"max_fps":{s.max_fps},"vsync":{json.dumps(s.vsync)},"fullscreen":{json.dumps(s.fullscreen)},'
        f'"graphics":{jstr(s.graphics)}}}');
}

impl summary_json(s: Summary) -> str {
    return (f'{{"count":{s.count},"p50_ms":{f32_json(s.p50_ms)},"p95_ms":{f32_json(s.p95_ms)},'
        f'"p99_ms":{f32_json(s.p99_ms)},"max_ms":{f32_json(s.max_ms)},'
        f'"buckets":[{",".join(str(b) for b in s.buckets)}]}}');
}

impl slow_json(s: SlowFrames) -> str {
    return (f'{{"span":{jstr(s.span)},"frames":{s.frames},"frame_max_ms":{f32_json(s.frame_max_ms)},'
        f'"span_max_ms":{f32_json(s.span_max_ms)}}}');
}

impl opt_json(name: str, v: u32 | None) -> str {
    return f',"{name}":{v}' if v is not None else "";
}

impl perf_json(p: Perf) -> str {
    ticks = f',"ticks":{summary_json(p.ticks)}' if p.ticks is not None else "";
    slow = (
        f',"slow_frames":[{",".join(slow_json(s) for s in p.slow_frames)}]' if p.slow_frames else ""
    );
    return (f'{{"system":{system_json(p.system)},"settings":{settings_json(p.settings)},'
        f'"seconds":{p.seconds},"frames":{summary_json(p.frames)}{ticks},'
        f'"peak_ram_mb":{p.peak_ram_mb}{opt_json("to_title_ms", p.to_title_ms)}'
        f'{opt_json("to_core_ms", p.to_core_ms)}{opt_json("to_rest_ms", p.to_rest_ms)}'
        f'{opt_json("to_world_ms", p.to_world_ms)}{slow}}}');
}

impl crash_json(c: Crash) -> str {
    details = ",".join(f"[{jstr(a)},{jstr(b)}]" for (a, b) in c.details);
    return (f'{{"system":{system_json(c.system)},"error":{jstr(c.error)},"stack":{jstr(c.stack)},'
        f'"thread":{jstr(c.thread)},"details":[{details}]}}');
}

impl bug_json(b: Bug) -> str {
    log = f',"log":{jstr(b.log)}' if b.log is not None else "";
    return f'{{"system":{system_json(b.system)},"text":{jstr(b.text)}{log}}}';
}

impl data_json(it: Item) -> str {
    if it.perf is not None {
        return perf_json(it.perf);
    }
    if it.crash is not None {
        return crash_json(it.crash);
    }
    if it.bug is not None {
        return bug_json(it.bug);
    }
    return it.benchmark;
}

impl item_json(it: Item) -> str {
    return (f'{{"day":{it.day},"source":{jstr(it.source.name.lower())},"version":{jstr(it.version)},'
        f'"kind":{jstr(kind_name(it.kind))},"data":{data_json(it)}}}');
}

impl record_slow(spans: list[SlowFrames], frame_ms: f32, span: str, span_ms: f32) {
    name = SLOW_OTHER if len(span.encode()) > SLOW_MAX_NAME else span;
    at = -1;
    for (i, s) in enumerate(spans) {
        if s.span == name {
            at = i;
        }
    }
    if at < 0 and len(spans) + 1 < SLOW_MAX_SPANS {
        spans.append(SlowFrames(span=name));
        at = len(spans) - 1;
    }
    if at < 0 {
        for (i, s) in enumerate(spans) {
            if s.span == SLOW_OTHER {
                at = i;
            }
        }
        if at < 0 {
            spans.append(SlowFrames(span=SLOW_OTHER));
            at = len(spans) - 1;
        }
    }
    slot = spans[at];
    slot.frames = slot.frames +| u32(1);
    slot.frame_max_ms = max(slot.frame_max_ms, frame_ms);
    slot.span_max_ms = max(slot.span_max_ms, span_ms);
}

impl Timings.record(ms: f32) {
    if not math.isfinite(float(ms)) or ms < f32(0.0) {
        return;
    }
    bin = min(int(ms * f32(10.0)), len(self.tenths) - 1);
    self.tenths[bin] += 1;
    self.count += 1;
    self.max_ms = max(self.max_ms, ms);
}

impl Timings.percentile(p: float) -> f32 {
    rank = max(int(math.ceil(float(self.count) * p)), 1);
    seen = 0;
    for (bin, n) in enumerate(self.tenths) {
        seen += n;
        if seen >= rank {
            if bin + 1 == len(self.tenths) {
                return self.max_ms;
            }
            return min(f32(bin + 1) / f32(10.0), self.max_ms);
        }
    }
    return self.max_ms;
}

impl Timings.summary -> Summary {
    edges = [f32(e) for e in BUCKET_EDGES_MS];
    counts = [0] * BUCKETS;
    for (bin, n) in enumerate(self.tenths) {
        ms = f32(bin) / f32(10.0);
        bucket = len(edges);
        for (i, top) in enumerate(edges) {
            if ms < top - f32(0.01) {
                bucket = i;
                break;
            }
        }
        counts[bucket] += n;
    }
    return Summary(
        count=u64(self.count),
        p50_ms=tenth32(self.percentile(0.50)),
        p95_ms=tenth32(self.percentile(0.95)),
        p99_ms=tenth32(self.percentile(0.99)),
        max_ms=tenth32(self.max_ms),
        buckets=[u32(c) for c in counts],
    );
}

impl tenth32(ms: f32) -> f32 {
    return f32(round_away(float(ms * f32(10.0)))) / f32(10.0);
}

impl round_away(x: float) -> float {
    if not math.isfinite(x) {
        return x;
    }
    t = float(math.trunc(x));
    if abs(x - t) >= 0.5 {
        t += math.copysign(1.0, x);
    }
    return t;
}

impl tenth(x: float) -> float {
    return round_away(x * 10.0) / 10.0;
}
