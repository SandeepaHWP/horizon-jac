"""A checked ping of session `n`."""
def ping(n: int, version: str, platform: str, lan: bool) -> Ping {
    return Ping(session=f"{n:032x}", version=version, platform=platform, lan=lan);
}

test "sessions count until the window passes" {
    sessions.clear();
    live_ping(ping(1, "0.2.0", "linux", False), 0.0, 120, 100);
    live_ping(ping(2, "0.2.0", "macos", True), 0.0, 120, 100);
    live_ping(ping(1, "0.2.0", "linux", False), 60.0, 120, 100);
    c = live_count(61.0, 120);
    assert (c.playing, c.lan) == (2, 1) and c.versions == {"0.2.0": 2};
    assert c.platforms == {"linux": 1, "macos": 1};
    c = live_count(150.0, 120);
    assert (c.playing, c.lan) == (1, 0) and len(sessions) == 1;
    assert live_count(181.0, 120) == Count() and len(sessions) == 0;
}

test "a full table takes no new session until one expires" {
    sessions.clear();
    assert live_ping(ping(1, "0.2.0", "linux", False), 0.0, 120, 2);
    assert live_ping(ping(2, "0.2.0", "linux", False), 0.0, 120, 2);
    assert not live_ping(ping(3, "0.2.0", "linux", False), 0.0, 120, 2);
    assert live_ping(ping(1, "0.2.0", "linux", False), 100.0, 120, 2);
    assert live_ping(ping(3, "0.2.0", "linux", False), 130.0, 120, 2);
    assert live_count(130.0, 120).playing == 2;
}

test "rare versions are summed and counts exact" {
    sessions.clear();
    for n in range(41) {
        live_ping(ping(n, "0.2.0", "windows", n % 4 == 0), 0.0, 120, 1000);
    }
    for n in range(VERSIONS_SHOWN + 3) {
        live_ping(ping(100 + n, f"dev {n}", "other", False), 0.0, 120, 1000);
    }
    c = live_count(0.0, 120);
    assert c.playing == 56 and c.lan == 11;
    assert c.versions["0.2.0"] == 41 and c.versions["other"] == 4;
    assert len(c.versions) == VERSIONS_SHOWN + 1;
    assert c.platforms["windows"] == 41 and c.platforms["other"] == 15;
}
