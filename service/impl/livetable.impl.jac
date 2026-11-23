impl live_ping(p: Ping, now: float, window: int, most: int) -> bool {
    if p.session not in sessions and len(sessions) >= most {
        live_forget(now, window);
        if len(sessions) >= most {
            return False;
        }
    }
    platform = PLATFORMS.index(p.platform) if p.platform in PLATFORMS else len(PLATFORMS) - 1;
    sessions[p.session] = Seen(at=now, version=p.version, platform=platform, lan=p.lan);
    return True;
}

impl live_forget(now: float, window: int) {
    for id in list(sessions.keys()) {
        if max(now - sessions[id].at, 0.0) >= float(window) {
            del sessions[id];
        }
    }
}

impl live_count(now: float, window: int) -> Count {
    live_forget(now, window);
    versions: dict[str, int] = {};
    platforms = [0, 0, 0, 0];
    lan = 0;
    for s in sessions.values() {
        versions[s.version] = versions.get(s.version, 0) + 1;
        platforms[s.platform] += 1;
        lan += 1 if s.lan else 0;
    }
    ranked = sorted(
        versions.items(), key=lambda (v: tuple[str, int]) -> tuple[int, str] { (-v[1], v[0]) }
    );
    shown: dict[str, int] = {};
    other = 0;
    for (i, (version, n)) in enumerate(ranked) {
        if i < VERSIONS_SHOWN {
            shown[version] = n;
        } else {
            other += n;
        }
    }
    if other > 0 {
        shown["other"] = shown.get("other", 0) + other;
    }
    return Count(
        playing=len(sessions),
        lan=lan,
        versions=shown,
        platforms={p: n for (p, n) in zip(PLATFORMS, platforms) if n > 0},
    );
}
