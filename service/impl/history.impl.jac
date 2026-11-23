impl sample_of(c: Count) -> Sample {
    return Sample(
        playing=c.playing, lan=c.lan, platforms=[c.platforms.get(p, 0) for p in PLATFORMS]
    );
}

impl rows_of(series: str, table: str) -> dict[int, any] {
    name = f"{series}.{table}";
    if name not in live_rows {
        found: dict[int, any] = {};
        if table == "minute" {
            for m in [hub(name) --> [?:Minute]] {
                found[m.t] = m;
            }
        } else {
            for r in [hub(name) --> [?:Roll]] {
                found[r.t] = r;
            }
        }
        live_rows[name] = found;
    }
    return live_rows[name];
}

impl rows(series: str, table: str) -> list[Row] {
    out: list[Row] = [];
    for (t, v) in rows_of(series, table).items() {
        if isinstance(v, Minute) {
            m: Minute = v;
            out.append(Row(t=t, samples=1, total=m.playing, peak=m.playing, peak_at=t, platform_sums=m.platforms));
        } else {
            r: Roll = v;
            out.append(Row(t=t, samples=r.samples, total=r.total, peak=r.peak, peak_at=r.peak_at, platform_sums=r.platform_sums));
        }
    }
    return out;
}

impl record_live(series: str, unix: int, sample: Sample) -> bool {
    minute = unix - unix % 60;
    minutes = rows_of(series, "minute");
    if minute in minutes {
        return False;
    }
    m = Minute(t=minute, playing=sample.playing, lan=sample.lan, platforms=list(sample.platforms));
    hub(f"{series}.minute") ++> m;
    minutes[minute] = m;
    for (table, start) in [("hour", minute - minute % HOUR), ("day", minute - minute % DAY_SECONDS)] {
        held = rows_of(series, table);
        if start not in held {
            fresh_roll = Roll(t=start, peak=sample.playing, peak_at=minute, lan_peak=sample.lan);
            hub(f"{series}.{table}") ++> fresh_roll;
            held[start] = fresh_roll;
        }
        r: Roll = held[start];
        if r.samples > 0 {
            if sample.playing > r.peak {
                r.peak_at = minute;
            }
            r.peak = max(r.peak, sample.playing);
            r.lan_peak = max(r.lan_peak, sample.lan);
        }
        r.samples += 1;
        r.total += sample.playing;
        r.lan_sum += sample.lan;
        r.platform_sums = [a + b for (a, b) in zip(r.platform_sums, sample.platforms)];
    }
    return True;
}

impl prune_live(now: int, minute_days: int, hour_days: int) -> int {
    removed = 0;
    for series in ["players", "official"] {
        for (table, days) in [("minute", minute_days), ("hour", hour_days)] {
            held = rows_of(series, table);
            for t in list(held.keys()) {
                if t < now - days * DAY_SECONDS {
                    remove(held[t]);
                    del held[t];
                    removed += 1;
                }
            }
        }
    }
    return removed;
}

impl live_history(series: str, range_name: str, now: int) -> str | None {
    plans = {
        "24h": ("minute", 300, DAY_SECONDS),
        "7d": ("hour", HOUR, 7 * DAY_SECONDS),
        "30d": ("hour", 3 * HOUR, 30 * DAY_SECONDS),
        "all": ("day", DAY_SECONDS, 0)
    };
    if range_name not in plans or series not in ["players", "official"] {
        return None;
    }
    (table, step, span) = plans[range_name];
    start = 0;
    if span > 0 {
        start = now - span;
        start -= start % step;
    }
    window = [r for r in rows(series, table) if r.t >= start];
    points: dict[int, list[int]] = {};
    for r in window {
        b = r.t // step * step;
        if b not in points {
            points[b] = [0, 0, 0];
        }
        points[b][0] += r.total;
        points[b][1] += r.samples;
        points[b][2] = max(points[b][2], r.peak);
    }
    def best(listed: list[Row]) -> dict[str, int] | None {
        if not listed {
            return None;
        }
        top = sorted(listed, key=lambda (r: Row) -> tuple[int, int] { (-r.peak, r.peak_at) })[0];
        return {"playing": max(top.peak, 0), "at": top.peak_at};
    }
    minutes = rows(series, "minute");
    latest: dict[str, int] | None = None;
    if minutes {
        newest = max(minutes, key=lambda (r: Row) -> int { r.t });
        latest = {"playing": max(newest.total, 0), "at": newest.t};
    }
    platforms: dict[str, float] = {};
    samples = sum(r.samples for r in window);
    if samples > 0 {
        for (i, p) in enumerate(PLATFORMS) {
            avg = tenth(float(sum(r.platform_sums[i] for r in window)) / float(samples));
            if avg > 0.0 {
                platforms[p] = avg;
            }
        }
    }
    def peak_json(p: dict[str, int] | None) -> str {
        return "null" if p is None else f'{{"playing":{p["playing"]},"at":{p["at"]}}}';
    }
    points_json = ",".join(
        f"[{b},{dumps(tenth(float(v[0]) / float(v[1])))},{max(v[2], 0)}]"
        for (b, v) in sorted(points.items())
    );
    return (
        f'{{"source":"{series}","range":"{range_name}","step":{step},"from":{start},"to":{now},'
        f'"series":[{points_json}],"peak":{peak_json(best(window))},'
        f'"all_time":{peak_json(best(rows(series, "day")))},"latest":{peak_json(latest)},'
        f'"platforms":{dumps(platforms)}}}'
    );
}
