impl trim(s: str) -> str {
    return " ".join(s.replace("(R)", "").replace("(TM)", "").replace("(tm)", "").split());
}

impl game(app: any) -> str | None {
    name = as_str(at(app, "name"));
    if name == "horizon-client" {
        return "horizon";
    }
    if name == "minecraft" {
        mods = at(app, "mods");
        if not isinstance(mods, list) {
            return "vanilla";
        }
        listed: list[any] = mods;
        if all(as_str(at(m, "name")) == "fabric-loader" for m in listed) {
            return "vanilla";
        }
    }
    return None;
}

impl rejection(doc: any) -> str | None {
    if as_str(at(doc, "format")) != "horizon-benchmark-report" or as_u64(at(doc, "version")) != 1 {
        return "not a version 1 benchmark report";
    }
    if as_str(at(doc, "kind")) != "game" {
        return "not a game run";
    }
    if game(at(doc, "app")) is None {
        return "not Horizon or plain vanilla";
    }
    c = at(doc, "conditions");
    scenario = as_str(at(c, "scenario")) or "";
    if not (scenario == "standard" or scenario == "flight" or scenario.startswith("perf_bench:")) {
        return "not the standard flight";
    }
    vsync = at(c, "vsync");
    if not (isinstance(vsync, bool) and vsync == False) {
        return "VSync on or unknown";
    }
    if isinstance(c, dict) and "fps_cap" in c and c["fps_cap"] is not None {
        return "frame rate capped";
    }
    offscreen = at(c, "offscreen");
    if isinstance(offscreen, bool) and offscreen == True {
        return "offscreen";
    }
    if as_f64(at(c, "render_distance")) is None {
        return "no render distance";
    }
    frames = at(doc, "frames");
    phases: set[str] = set();
    if isinstance(frames, list) {
        listed: list[any] = frames;
        for f in listed {
            p = as_str(at(f, "phase"));
            if p is not None {
                phases.add(p);
            }
        }
    }
    if not all(s in phases for s in SCENES) {
        return "not every scene";
    }
    hw = at(doc, "hardware");
    gpu_name = as_str(at(at(hw, "gpu"), "name"));
    cpu_name = as_str(at(hw, "cpu"));
    if gpu_name is None or trim(gpu_name) == "" or cpu_name is None or trim(cpu_name) == "" {
        return "no GPU or CPU name";
    }
    return None;
}

impl median(xs: list[float]) -> float | None {
    v = sorted(x for x in xs if math.isfinite(x));
    if not v {
        return None;
    }
    m = len(v) // 2;
    return v[m] if len(v) % 2 == 1 else (v[m - 1] + v[m]) / 2.0;
}

impl round_field(field: str, x: float) -> float {
    if field.endswith("_ms") and x < 10.0 {
        return tenth(x);
    }
    return round_away(x);
}

impl number(x: float) -> any {
    if x == math.floor(x) and abs(x) < 9e15 {
        return int(x);
    }
    return x;
}

impl figures(doc: any) -> list[float | None] {
    frames_v = at(doc, "frames");
    frames: list[any] = frames_v if isinstance(frames_v, list) else [];
    def avg(key: str) -> float | None {
        xs = [x for x in [as_f64(at(f, key)) for f in frames] if x is not None];
        return sum(xs) / len(xs) if xs else None;
    }
    metrics = at(doc, "metrics");
    def metric(name: str) -> float | None {
        return as_f64(at(at(metrics, name), "mean"));
    }
    loads: list[float] = [];
    if isinstance(metrics, dict) {
        m: dict[str, any] = metrics;
        for k in sorted(m.keys()) {
            if k.startswith("chunks.") and k.endswith(".load_ms") and len(k) >= len("chunks..load_ms") {
                scene = k[len("chunks."):len(k) - len(".load_ms")];
                if "." not in scene {
                    x = as_f64(at(m[k], "mean"));
                    if x is not None {
                        loads.append(x);
                    }
                }
            }
        }
    }
    return [
        avg("avg_fps"),
        avg("low_1pct_fps"),
        avg("p95_ms"),
        metric("startup.world_ms"),
        sum(loads) / len(loads) if loads else None,
        metric("memory.rss_peak_mb"),
        metric("memory.rss_steady_mb")
    ];
}

impl breakdowns(classes: list[dict[str, set[str]]], min_installs: int) -> dict[str, any] {
    out: dict[str, any] = {};
    for (dim, by_class) in zip(DIMENSIONS, classes) {
        cells = [(c, len(s)) for (c, s) in by_class.items() if len(s) >= min_installs];
        cells.sort(key=lambda (cell: tuple[str, int]) -> tuple[int, str] { (-cell[1], cell[0]) });
        if cells {
            out[dim] = [{"class": c, "installs": n} for (c, n) in cells];
        }
    }
    return out;
}

impl groups(uploads: list[Upload], min_installs: int) -> list[dict[str, any]] {
    grouped: dict[tuple[str, str, int, str], Group] = {};
    for u in uploads {
        if u.install == "" or rejection(u.doc) is not None {
            continue;
        }
        hw = at(u.doc, "hardware");
        rd = as_f64(at(at(u.doc, "conditions"), "render_distance")) or 0.0;
        key = (
            trim(as_str(at(at(hw, "gpu"), "name")) or ""),
            trim(as_str(at(hw, "cpu")) or ""),
            int(max(min(rd, 9.2e18), -9.2e18)),
            game(at(u.doc, "app")) or ""
        );
        if key not in grouped {
            grouped[key] = Group();
        }
        g = grouped[key];
        g.reports += 1;
        if u.version != "" {
            g.versions.add(u.version);
        }
        if u.install not in g.installs {
            g.installs[u.install] = [];
        }
        g.installs[u.install].append(figures(u.doc));
        for (dim, cls) in enumerate(of_report(u.doc)) {
            if cls is not None {
                if cls not in g.classes[dim] {
                    empty: set[str] = set();
                    g.classes[dim][cls] = empty;
                }
                g.classes[dim][cls].add(u.install);
            }
        }
    }
    out: list[tuple[int, dict[str, any]]] = [];
    for key in sorted(grouped.keys()) {
        g = grouped[key];
        if len(g.installs) < min_installs {
            continue;
        }
        per_install: list[list[float | None]] = [];
        for runs in g.installs.values() {
            per_install.append(
                [median([r[i] for r in runs if r[i] is not None]) for i in range(len(FIELDS))]
            );
        }
        medians: dict[str, any] = {};
        for (i, f) in enumerate(FIELDS) {
            m = median([r[i] for r in per_install if r[i] is not None]);
            medians[f] = number(round_field(f, m)) if m is not None else None;
        }
        versions = sorted(g.versions);
        def numbers(v: str) -> list[int] {
            parts: list[int] = [];
            digits = "";
            for ch in v + "x" {
                if ch.isdigit() and ch.isascii() {
                    digits += ch;
                } elif digits != "" {
                    parts.append(int(digits));
                    digits = "";
                }
            }
            return parts;
        }
        versions = sorted(versions, key=numbers, reverse=True)[:3];
        (gpu, cpu, rd, game_name) = key;
        out.append(
            (
                len(g.installs),
                {
                    "gpu": gpu,
                    "cpu": cpu,
                    "render_distance": rd,
                    "game": game_name,
                    "source": "players",
                    "installs": len(g.installs),
                    "reports": g.reports,
                    "versions": versions,
                    "medians": medians,
                    "breakdowns": breakdowns(g.classes, min_installs)
                }
            )
        );
    }
    out.sort(key=lambda (g: tuple[int, dict[str, any]]) -> int { -g[0] });
    return [g[1] for g in out];
}

impl summary(uploads: list[Upload], min_installs: int, generated: str) -> str {
    return dumps(
        {
            "format": FORMAT,
            "version": 1,
            "generated": generated,
            "min_installs": min_installs,
            "groups": groups(uploads, min_installs)
        }
    );
}
