"""A ping as the game sends it."""
def ping_text(session: str, version: str, platform: str, lan: bool) -> bytes {
    return json.dumps({
        "session": session,
        "version": version,
        "platform": platform,
        "lan": lan,
    }).encode();
}

test "a ping holds only the four fields" {
    p = ping_of(ping_text("a" * 32, "0.2.0", "linux", True));
    assert ping_check(p) is None;
    extra = b'{"session":"00000000000000000000000000000000","version":"0.2.0","platform":"linux","lan":false,"name":"Steve"}';
    refused = False;
    try {
        ping_of(extra);
    } except ValueError {
        refused = True;
    }
    assert refused;
}

test "bad pings are refused" {
    good = Ping(session="0" * 32, version="v2026.10.15", platform="linux", lan=False);
    assert ping_check(good) is None;
    for bad in [
        Ping(session="ABC", version="1", platform="linux", lan=False),
        Ping(session="G" * 32, version="1", platform="linux", lan=False),
        Ping(session="0" * 32, version="", platform="linux", lan=False),
        Ping(session="0" * 32, version="1" * 41, platform="linux", lan=False),
        Ping(session="0" * 32, version="<script>", platform="linux", lan=False),
        Ping(session="0" * 32, version="1", platform="haiku", lan=False),
    ] {
        assert ping_check(bad) is not None, str(bad);
    }
    assert ping_check(Ping(session="0" * 32, version="dev 0.1.0", platform="other", lan=True))
        is None;
}

test "a count is written as the original's struct" {
    c = Count(playing=2, lan=1, versions={"0.2.0": 2}, platforms={"macos": 1, "linux": 1});
    assert count_json(c)
        == '{"playing":2,"lan":1,"versions":{"0.2.0":2},"platforms":{"linux":1,"macos":1}}';
}
