impl forget_lookups {
    installs_by_key.clear();
    days_by_day.clear();
    machines_by_key.clear();
    machines_by_id.clear();
    hubs.clear();
    loaded.clear();
}

impl hub(name: str) -> Hub {
    if name in hubs {
        return hubs[name];
    }
    found = [h for h in [root.shared --> [?:Hub]] if h.name == name];
    h = found[0] if found else Hub(name=name);
    if not found {
        root.shared ++> h;
    }
    hubs[name] = h;
    return h;
}

impl counters -> Counters {
    found = [c for c in [hub("counters") --> [?:Counters]]];
    if found {
        return found[0];
    }
    c = Counters();
    hub("counters") ++> c;
    return c;
}

impl install_node(key: str) -> Install | None {
    if "installs" not in loaded {
        for i in [hub("installs") --> [?:Install]] {
            installs_by_key[i.key] = i;
        }
        loaded.add("installs");
    }
    return installs_by_key.get(key);
}

impl day_node(day: int, make: bool) -> Day | None {
    if "days" not in loaded {
        for d in [hub("days") --> [?:Day]] {
            days_by_day[d.day] = d;
        }
        loaded.add("days");
    }
    if day not in days_by_day and make {
        d = Day(day=day);
        hub("days") ++> d;
        days_by_day[day] = d;
    }
    return days_by_day.get(day);
}

impl all_days -> list[Day] {
    day_node(0, False);
    return [days_by_day[d] for d in sorted(days_by_day.keys())];
}

impl machine_of(id: str) -> Machine | None {
    if "machines" not in loaded {
        for m in [hub("machines") --> [?:Machine]] {
            machines_by_key[m.key] = m;
            machines_by_id[jid(m)] = m;
        }
        loaded.add("machines");
    }
    return machines_by_id.get(id);
}

impl pack(s: Summary) -> bytes {
    counts = [int(s.buckets[i]) if i < len(s.buckets) else 0 for i in range(BUCKET_COUNT)];
    return struct.pack(
        "<Q4f14I",
        int(s.count),
        float(s.p50_ms),
        float(s.p95_ms),
        float(s.p99_ms),
        float(s.max_ms),
        *counts
    );
}

impl unpack(raw: bytes) -> Summary | None {
    if len(raw) != 8 + 16 + 4 * BUCKET_COUNT {
        return None;
    }
    v = struct.unpack("<Q4f14I", raw);
    return Summary(
        count=u64(v[0]),
        p50_ms=f32(v[1]),
        p95_ms=f32(v[2]),
        p99_ms=f32(v[3]),
        max_ms=f32(v[4]),
        buckets=[u32(b) for b in v[5:]]
    );
}

impl gpu_vendor(gpu: str) -> str {
    g = gpu.lower();
    for (needle, vendor) in [
        ("apple", "apple"),
        ("nvidia", "nvidia"),
        ("geforce", "nvidia"),
        ("radeon", "amd"),
        ("amd", "amd"),
        ("intel", "intel"),
        ("adreno", "qualcomm"),
        ("llvmpipe", "software"),
    ] {
        if needle in g {
            return vendor;
        }
    }
    return "unknown" if g == "" else "other";
}

impl extra_json(s: System) -> str {
    shown = display_json(s.display) if s.display is not None else "null";
    return (
        f'{{"cores":{s.cores},"cpu_base_mhz":{s.cpu_base_mhz},"cpu_boost_mhz":{s.cpu_boost_mhz},'
        f'"gpu_vendor":{jstr(s.gpu_vendor)},"gpu_kind":{jstr(s.gpu_kind)},"vram_mb":{s.vram_mb},'
        f'"storage":{jstr(s.storage)},"display":{shown},"power":{jstr(s.power)},"form":{jstr(s.form)}}}'
    );
}

impl machine_for(s: System) -> Machine {
    machine_of("");
    extra = extra_json(s);
    key = json.dumps(
        [s.os, s.os_version, s.arch, s.cpu, int(s.threads), int(s.ram_gb), s.gpu, s.driver, s.backend, extra]
    );
    if key in machines_by_key {
        return machines_by_key[key];
    }
    m = Machine(
        key=key,
        os=s.os,
        os_version=s.os_version,
        arch=s.arch,
        cpu=s.cpu,
        threads=int(s.threads),
        ram_gb=int(s.ram_gb),
        gpu=s.gpu,
        driver=s.driver,
        backend=s.backend,
        extra=extra
    );
    hub("machines") ++> m;
    machines_by_key[key] = m;
    machines_by_id[jid(m)] = m;
    return m;
}

impl count_on(key: str, day: int) -> int {
    i = install_node(key);
    if i is None {
        return 0;
    }
    return len([s for s in [i --> [?:Session]] if s.day == day])
        + len([r for r in [i --> [?:Report]] if r.day == day]);
}

impl insert(b: Batch, day: int) {
    key = b.install_id;
    i = install_node(key);
    if i is None {
        i = Install(key=key);
        hub("installs") ++> i;
        installs_by_key[key] = i;
    }
    d = day_node(day, True);
    for it in b.items {
        if it.perf is not None {
            p = it.perf;
            m = machine_for(p.system);
            m.uses += 1;
            slow: str | None = None;
            if p.slow_frames {
                slow = "[" + ",".join(slow_json(x) for x in p.slow_frames) + "]";
            }
            s = Session(
                install=key,
                day=day,
                version=it.version,
                machine=jid(m),
                render_distance=int(p.settings.render_distance),
                simulation_distance=int(p.settings.simulation_distance),
                max_fps=int(p.settings.max_fps),
                vsync=p.settings.vsync,
                fullscreen=p.settings.fullscreen,
                graphics=p.settings.graphics,
                seconds=int(p.seconds),
                frames=pack(p.frames),
                ticks=pack(p.ticks) if p.ticks is not None else None,
                peak_ram_mb=int(p.peak_ram_mb),
                to_title_ms=int(p.to_title_ms) if p.to_title_ms is not None else None,
                to_world_ms=int(p.to_world_ms) if p.to_world_ms is not None else None,
                slow_frames=slow
            );
            i ++> s;
            d ++> s;
        } else {
            machine = "";
            if it.crash is not None or it.bug is not None {
                system = it.crash.system if it.crash is not None else it.bug.system;
                m = machine_for(system);
                m.uses += 1;
                machine = jid(m);
            }
            c = counters();
            r = Report(
                id=c.next_report,
                install=key,
                day=day,
                kind=it.kind.value,
                version=it.version,
                machine=machine,
                body=compression.zstd.compress(data_json(it).encode())
            );
            c.next_report += 1;
            i ++> r;
            d ++> r;
        }
    }
    d.dirty = True;
}

impl delete_install(key: str) -> int {
    i = install_node(key);
    if i is None {
        return 0;
    }
    deleted = 0;
    for s in [i --> [?:Session]] {
        d = day_node(s.day, False);
        if d is not None {
            d.dirty = True;
        }
        release(s.machine);
        remove(s);
        deleted += 1;
    }
    for r in [i --> [?:Report]] {
        release(r.machine);
        remove(r);
        deleted += 1;
    }
    remove(i);
    del installs_by_key[key];
    rebuild_dirty();
    return deleted;
}

impl release(id: str) {
    m = machine_of(id);
    if m is None {
        return;
    }
    m.uses -= 1;
    if m.uses <= 0 {
        del machines_by_key[m.key];
        del machines_by_id[id];
        remove(m);
    }
}

impl expire(oldest_day: int) -> int {
    rebuild_dirty();
    removed = 0;
    for d in all_days() {
        if d.day >= oldest_day {
            break;
        }
        for s in [d --> [?:Session]] {
            release(s.machine);
            remove(s);
            removed += 1;
        }
        for r in [d --> [?:Report]] {
            release(r.machine);
            remove(r);
            removed += 1;
        }
    }
    if removed > 0 {
        for i in list(installs_by_key.values()) {
            if not [i --> [?:Session]] and not [i --> [?:Report]] {
                del installs_by_key[i.key];
                remove(i);
            }
        }
    }
    return removed;
}

impl rebuild_dirty {
    for d in all_days() {
        if d.dirty {
            rebuild_day(d);
        }
    }
}

impl rebuild_day(d: Day) {
    grouped: dict[tuple[str, str, str, int], DayGroup] = {};
    seen: dict[tuple[str, str, str, int], set[str]] = {};
    for s in [d --> [?:Session]] {
        frames = unpack(s.frames);
        m = machine_of(s.machine);
        if frames is None or m is None {
            continue;
        }
        key = (s.version, m.os, gpu_vendor(m.gpu), s.render_distance);
        if key not in grouped {
            grouped[key] = DayGroup(
                version=key[0],
                os=key[1],
                gpu_vendor=key[2],
                render_distance=key[3],
                buckets=[0] * BUCKET_COUNT
            );
            empty: set[str] = set();
            seen[key] = empty;
        }
        g = grouped[key];
        g.sessions += 1;
        seen[key].add(s.install);
        g.seconds += s.seconds;
        for (n, b) in enumerate(frames.buckets) {
            g.buckets[n] += int(b);
        }
        g.p50_sum += float(frames.p50_ms);
        g.p99_sum += float(frames.p99_ms);
    }
    for (key, g) in grouped.items() {
        g.installs = len(seen[key]);
    }
    d.totals = list(grouped.values());
    d.dirty = False;
}

impl sessions_in(start: int, end: int) -> list[Session] {
    out: list[Session] = [];
    for d in all_days() {
        if start <= d.day <= end {
            out.extend([d --> [?:Session]]);
        }
    }
    return out;
}

impl aggregate(start: int, end: int, k: int) -> str {
    rebuild_dirty();
    totals: dict[tuple[str, str, str, int], DayGroup] = {};
    for d in all_days() {
        if not (start <= d.day <= end) {
            continue;
        }
        for g in d.totals {
            key = (g.version, g.os, g.gpu_vendor, g.render_distance);
            if key not in totals {
                totals[key] = DayGroup(
                    version=g.version,
                    os=g.os,
                    gpu_vendor=g.gpu_vendor,
                    render_distance=g.render_distance,
                    buckets=[0] * BUCKET_COUNT
                );
            }
            t = totals[key];
            t.sessions += g.sessions;
            t.installs += g.installs;
            t.seconds += g.seconds;
            for (n, b) in enumerate(g.buckets) {
                t.buckets[n] += b;
            }
            t.p50_sum += g.p50_sum;
            t.p99_sum += g.p99_sum;
        }
    }
    sessions = 0;
    hours = 0.0;
    groups: list[dict[str, any]] = [];
    for t in totals.values() {
        if t.installs < k {
            continue;
        }
        sessions += t.sessions;
        hours += float(t.seconds) / 3600.0;
        groups.append(
            {
                "version": t.version,
                "os": t.os,
                "gpu_vendor": t.gpu_vendor,
                "render_distance": t.render_distance,
                "sessions": t.sessions,
                "install_days": t.installs,
                "hours": round_away(float(t.seconds) / 360.0) / 10.0,
                "frame_buckets": t.buckets,
                "p50_ms": tenth(t.p50_sum / float(t.sessions)),
                "p99_ms": tenth(t.p99_sum / float(t.sessions))
            }
        );
    }
    groups.sort(key=lambda (g: dict[str, any]) -> int { -g["sessions"] });
    crashes: dict[str, int] = {};
    for d in all_days() {
        if start <= d.day <= end {
            for r in [d --> [?:Report]] {
                if r.kind == Kind.CRASH.value {
                    crashes[r.version] = crashes.get(r.version, 0) + 1;
                }
            }
        }
    }
    by_count = sorted(crashes.items(), key=lambda (c: tuple[str, int]) -> tuple[int, str] { (-c[1], c[0]) });
    return dumps(
        {
            "from_day": start,
            "to_day": end,
            "min_install_days": k,
            "bucket_edges_ms": [tenth(float(f32(e))) for e in BUCKET_EDGES_MS],
            "totals": {"sessions": sessions, "hours": tenth(hours)},
            "groups": groups,
            "crashes_by_version": [{"version": v, "crashes": n} for (v, n) in by_count[:20]],
            "breakdowns": breakdowns(start, end),
            "slow_frames": slow_frames(start, end, k)
        }
    );
}

impl slow_frames(start: int, end: int, k: int) -> list[dict[str, any]] {
    steps: dict[tuple[str, str], StepTotals] = {};
    for s in sessions_in(start, end) {
        if s.slow_frames is None {
            continue;
        }
        listed: list[any] = json.loads(s.slow_frames);
        for raw in listed {
            v: dict[str, any] = raw;
            key = (s.version, v.get("span", ""));
            if key not in steps {
                steps[key] = StepTotals();
            }
            st = steps[key];
            st.frames += int(v.get("frames", 0));
            st.sessions += 1;
            st.installs.add(s.install);
            st.frame_max_ms = max(st.frame_max_ms, float(f32(v.get("frame_max_ms", 0.0))));
            st.span_max_ms = max(st.span_max_ms, float(f32(v.get("span_max_ms", 0.0))));
        }
    }
    kept = [(key, st) for (key, st) in steps.items() if len(st.installs) >= k];
    kept.sort(
        key=lambda (e: tuple[tuple[str, str], StepTotals]) -> tuple[int, str, str] {
            (-e[1].frames, e[0][0], e[0][1])
        }
    );
    return [
        {
            "version": key[0],
            "span": key[1],
            "frames": st.frames,
            "sessions": st.sessions,
            "installs": len(st.installs),
            "frame_max_ms": tenth(st.frame_max_ms),
            "span_max_ms": tenth(st.span_max_ms)
        }
        for (key, st) in kept
    ];
}

impl breakdowns(start: int, end: int) -> dict[str, any] {
    cells: list[dict[str, ClassTotals]] = [{}, {}, {}, {}, {}];
    for s in sessions_in(start, end) {
        frames = unpack(s.frames);
        m = machine_of(s.machine);
        if frames is None or m is None {
            continue;
        }
        extra: dict[str, any] = json.loads(m.extra);
        system = System(
            os=m.os,
            ram_gb=u16(m.ram_gb),
            gpu_kind=extra.get("gpu_kind", ""),
            vram_mb=u32(extra.get("vram_mb", 0)),
            storage=extra.get("storage", "")
        );
        for (n, cls) in enumerate(of_system(system)) {
            if cls is None {
                continue;
            }
            if cls not in cells[n] {
                cells[n][cls] = ClassTotals();
            }
            c = cells[n][cls];
            c.installs.add(s.install);
            c.sessions += 1;
            c.seconds += s.seconds;
            c.p50_sum += float(frames.p50_ms);
            c.p99_sum += float(frames.p99_ms);
        }
    }
    out: dict[str, any] = {};
    for (dim, by_class) in zip(DIMENSIONS, cells) {
        listed = [(cls, c) for (cls, c) in by_class.items() if len(c.installs) >= MIN_INSTALLS];
        listed.sort(
            key=lambda (e: tuple[str, ClassTotals]) -> tuple[int, str] { (-len(e[1].installs), e[0]) }
        );
        if listed {
            out[dim] = [
                {
                    "class": cls,
                    "installs": len(c.installs),
                    "sessions": c.sessions,
                    "hours": round_away(float(c.seconds) / 360.0) / 10.0,
                    "p50_ms": tenth(c.p50_sum / float(c.sessions)),
                    "p99_ms": tenth(c.p99_sum / float(c.sessions))
                }
                for (cls, c) in listed
            ];
        }
    }
    return out;
}

impl inflate(body: bytes) -> any {
    try {
        return json.loads(compression.zstd.decompress(body).decode("utf-8"));
    } except Exception {
        return None;
    }
}

impl benchmark_uploads(from_day: int) -> list[Upload] {
    out: list[Upload] = [];
    for d in all_days() {
        if d.day >= from_day {
            for r in [d --> [?:Report]] {
                if r.kind == Kind.BENCHMARK.value {
                    out.append(Upload(install=r.install, version=r.version, doc=inflate(r.body)));
                }
            }
        }
    }
    return out;
}

impl newest_day(key: str) -> int | None {
    i = install_node(key);
    if i is None {
        return None;
    }
    days = [s.day for s in [i --> [?:Session]]] + [r.day for r in [i --> [?:Report]]];
    return max(days) if days else None;
}

impl export_benchmarks(after: int, limit: int) -> list[dict[str, any]] {
    found: list[Report] = [];
    for d in all_days() {
        for r in [d --> [?:Report]] {
            if r.kind == Kind.BENCHMARK.value and r.id > after {
                found.append(r);
            }
        }
    }
    found.sort(key=lambda (r: Report) -> int { r.id });
    return [
        {"id": r.id, "day": r.day, "version": r.version, "report": inflate(r.body)}
        for r in found[:limit]
    ];
}

impl export_machines(start: int, end: int) -> list[dict[str, any]] {
    machines: dict[str, MachineTotals] = {};
    for s in sessions_in(start, end) {
        frames = unpack(s.frames);
        m = machine_of(s.machine);
        if frames is None or m is None {
            continue;
        }
        extra: dict[str, any] = json.loads(m.extra);
        description: dict[str, any] = {
            "os": m.os,
            "os_version": m.os_version,
            "arch": m.arch,
            "cpu": m.cpu,
            "threads": m.threads,
            "cores": extra.get("cores", 0),
            "cpu_base_mhz": extra.get("cpu_base_mhz", 0),
            "cpu_boost_mhz": extra.get("cpu_boost_mhz", 0),
            "ram_gb": m.ram_gb,
            "gpu": m.gpu,
            "gpu_vendor": extra.get("gpu_vendor", ""),
            "gpu_kind": extra.get("gpu_kind", ""),
            "vram_mb": extra.get("vram_mb", 0),
            "driver": m.driver,
            "backend": m.backend,
            "storage": extra.get("storage", ""),
            "form": extra.get("form", "")
        };
        key = dumps(description);
        if key not in machines {
            machines[key] = MachineTotals(description=description, buckets=[0] * len(frames.buckets));
        }
        e = machines[key];
        e.installs.add(s.install);
        e.sessions += 1;
        e.seconds += s.seconds;
        e.p50_sum += float(frames.p50_ms);
        e.p99_sum += float(frames.p99_ms);
        for (n, b) in enumerate(frames.buckets) {
            e.buckets[n] += int(b);
        }
        e.peak_ram_mb = max(e.peak_ram_mb, s.peak_ram_mb);
    }
    listed = sorted(
        machines.items(),
        key=lambda (e: tuple[str, MachineTotals]) -> tuple[int, str] { (-e[1].sessions, e[0]) }
    );
    out: list[dict[str, any]] = [];
    for (_, e) in listed {
        row: dict[str, any] = dict(e.description);
        row["installs"] = len(e.installs);
        row["sessions"] = e.sessions;
        row["hours"] = round_away(float(e.seconds) / 360.0) / 10.0;
        row["p50_ms"] = tenth(e.p50_sum / float(e.sessions));
        row["p99_ms"] = tenth(e.p99_sum / float(e.sessions));
        row["peak_ram_mb"] = e.peak_ram_mb;
        row["frame_buckets"] = e.buckets;
        out.append(row);
    }
    return out;
}
