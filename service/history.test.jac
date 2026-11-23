import json;
import from service.store { Hub, forget_lookups }

glob START: int = 20000 * 86400;

"""A sample of `playing`, half of them on LAN, `linux` of them on Linux and the rest on macOS."""
def sample(playing: int, linux: int) -> Sample {
    return Sample(playing=playing, lan=playing // 2, platforms=[linux, playing - linux, 0, 0]);
}

"""Starts again on an empty graph."""
def fresh {
    for h in [root.shared --> [?:Hub]] {
        remove(h);
    }
    forget_lookups();
    live_rows.clear();
}

"""A history as its JSON value."""
def history(series: str, range_name: str, now: int) -> dict[str, any] {
    text = live_history(series, range_name, now);
    assert text is not None;
    return json.loads(text);
}

test "a minute is recorded once and rolls up" {
    fresh();
    assert record_live("players", START + 10, sample(4, 1));
    assert not record_live("players", START + 59, sample(9, 9)), "a late tick changes nothing";
    record_live("players", START + 60, sample(8, 2));
    record_live("players", START + 120, sample(8, 8));
    record_live("players", START + HOUR, sample(2, 0));
    now = START + HOUR + 30;
    h = history("players", "24h", now);
    assert h["series"] == [[START, 6.7, 8], [START + HOUR, 2.0, 2]], str(h["series"]);
    assert h["peak"] == {"playing": 8, "at": START + 60};
    assert h["all_time"] == h["peak"];
    assert h["platforms"]["linux"] == 2.8 and h["platforms"]["macos"] == 2.8;
    assert "windows" not in h["platforms"];
    week = history("players", "7d", now);
    assert week["series"] == [[START, 6.7, 8], [START + HOUR, 2.0, 2]];
    assert week["peak"] == h["peak"];
    all = history("players", "all", now);
    assert all["series"] == [[START, 5.5, 8]] and all["step"] == 86400;
}

test "old minutes and hours go and days stay" {
    fresh();
    record_live("players", START, sample(30, 0));
    later = START + 100 * 86400;
    record_live("players", later, sample(3, 0));
    assert prune_live(later, 7, 90) == 2;
    all = history("players", "all", later);
    assert all["series"] == [[START, 30.0, 30], [later, 3.0, 3]];
    assert all["all_time"]["playing"] == 30;
    day = history("players", "24h", later + 60);
    assert day["series"] == [[later, 3.0, 3]];
    assert day["peak"]["playing"] == 3 and day["all_time"]["at"] == START;
}

test "an empty history has no peak" {
    fresh();
    h = history("players", "30d", START);
    assert h["series"] == []
        and h["peak"] is None
        and h["all_time"] is None
        and h["latest"] is None;
    assert h["platforms"] == {};
    assert live_history("players", "1y", START) is None
        and live_history("lan", "24h", START) is None;
}

test "the official series is kept apart" {
    fresh();
    record_live("players", START, sample(40, 10));
    assert record_live("official", START, Sample(playing=6));
    h = history("official", "24h", START + 60);
    assert h["series"] == [[START, 6.0, 6]] and h["all_time"]["playing"] == 6;
    assert h["latest"] == {"playing": 6, "at": START};
    assert h["platforms"] == {};
    assert history("players", "24h", START + 60)["all_time"]["playing"] == 40;
    assert prune_live(START + 100 * 86400, 7, 90) == 4;
}

test "a history is written as the original's struct" {
    fresh();
    record_live("players", START, sample(3, 1));
    text = live_history("players", "24h", START + 30);
    assert text
        == f'{{"source":"players","range":"24h","step":300,"from":{START + 30 - 86400 - (START + 30 - 86400) % 300},"to":{START + 30},"series":[[{START},3.0,3]],"peak":{{"playing":3,"at":{START}}},"all_time":{{"playing":3,"at":{START}}},"latest":{{"playing":3,"at":{START}}},"platforms":{{"linux":1.0,"macos":2.0}}}}', text;
}
