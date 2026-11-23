import json;

"""A perf item with a session of `n` frames from 8 to 13 ms."""
def bug_item(text: str) -> Item {
    return Item(
        day=u32(20741), source=Source.GAME, version="v1", kind=Kind.BUG, bug=Bug(text=text)
    );
}

test "items are tagged by kind and read back" {
    it = Item(
        day=u32(20741),
        source=Source.GAME,
        version="v0.4.2",
        kind=Kind.BUG,
        bug=Bug(text="Water flickers"),
    );
    v: dict[str, any] = json.loads(item_json(it));
    assert v["kind"] == "bug" and v["source"] == "game";
    data: dict[str, any] = v["data"];
    assert data["text"] == "Water flickers";
    assert item_of(v) == it;
}

test "a benchmark report is carried as it is" {
    doc = {"schema": "horizon-benchmark-report/1", "scenes": []};
    v = {"day": 1, "source": "launcher", "version": "0.1.5", "kind": "benchmark", "data": doc};
    it = item_of(v);
    assert json.loads(it.benchmark) == doc;
    assert validate(it) is None;
    v["data"] = 1;
    assert validate(item_of(v)) is not None;
}

test "oversized items are refused" {
    assert validate(bug_item("x" * BUG_MAX_TEXT)) is None;
    assert validate(bug_item("x" * (BUG_MAX_TEXT + 1))) is not None;
    assert validate(bug_item("  ")) is not None;
    huge = Item(
        day=u32(1),
        source=Source.GAME,
        version="v1",
        kind=Kind.CRASH,
        crash=Crash(stack="frame\n" * 10000),
    );
    why = validate(huge);
    assert why is not None and "over its" in why;
}

test "timings give percentiles and buckets" {
    t = Timings();
    for _ in range(90) {
        t.record(f32(16.6));
    }
    for _ in range(9) {
        t.record(f32(30.0));
    }
    t.record(f32(400.0));
    t.record(f32(math.nan));
    s = t.summary();
    assert s.count == u64(100);
    assert (s.p50_ms, s.p95_ms, s.p99_ms, s.max_ms)
        == (f32(16.7), f32(30.1), f32(30.1), f32(400.0));
    assert len(s.buckets) == 14;
    assert (s.buckets[6], s.buckets[9], s.buckets[13]) == (u32(90), u32(9), u32(1));
    assert sum(int(b) for b in s.buckets) == 100;
}

test "hitches beyond the fine range keep their maximum" {
    t = Timings();
    t.record(f32(2000.0));
    s = t.summary();
    assert (s.p50_ms, s.max_ms) == (f32(2000.0), f32(2000.0));
    assert s.buckets[13] == u32(1);
}

test "a session summary is small" {
    t = Timings();
    for i in range(200000) {
        t.record(f32(5.0) + f32(i % 300) / f32(10.0));
    }
    it = Item(
        day=u32(1),
        source=Source.GAME,
        version="v0.4.2",
        kind=Kind.PERF,
        perf=Perf(frames=t.summary(), ticks=t.summary()),
    );
    assert len(item_json(it).encode()) < 1024;
    assert validate(it) is None;
}

test "slow frames are counted by span within a cap" {
    spans: list[SlowFrames] = [];
    record_slow(spans, f32(300.0), "render.upload", f32(200.0));
    record_slow(spans, f32(900.0), "render.upload", f32(120.0));
    record_slow(spans, f32(260.0), "", f32(0.0));
    assert spans[0]
        == SlowFrames(
            span="render.upload", frames=u32(2), frame_max_ms=f32(900.0), span_max_ms=f32(200.0)
        );
    assert (spans[1].span, spans[1].frames) == ("", u32(1));
    for i in range(40) {
        record_slow(spans, f32(400.0), f"step.{i}", f32(300.0));
    }
    record_slow(spans, f32(400.0), "x" * 200, f32(300.0));
    assert len(spans) == SLOW_MAX_SPANS;
    other = [s for s in spans if s.span == SLOW_OTHER][0];
    assert other.frames == u32(40 - 13 + 1);
    ok = Item(
        day=u32(1),
        source=Source.GAME,
        version="v0.4.2",
        kind=Kind.PERF,
        perf=Perf(slow_frames=spans),
    );
    assert validate(ok) is None;
    too_many = Item(
        day=u32(1),
        source=Source.GAME,
        version="v0.4.2",
        kind=Kind.PERF,
        perf=Perf(slow_frames=spans + spans),
    );
    assert validate(too_many) is not None;
}

test "rounding takes halves away from zero, as Rust's does" {
    assert (round_away(2.5), round_away(-2.5), round_away(98.5), round_away(0.49999999999999994))
        == (3.0, -3.0, 99.0, 0.0);
    assert tenth(3.46) == 3.5 and tenth(0.25) == 0.3;
}
