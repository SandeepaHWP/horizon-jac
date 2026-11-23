import json;

"""The shared fixtures' items, one JSON object a line."""
def items -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    with open("test/fixtures/benchmarks/items.jsonl") as f {
        for line in f {
            if line.strip() != "" {
                out.append(json.loads(line));
            }
        }
    }
    return out;
}

test "the fixtures give the website's groups" {
    uploads = [
        Upload(
            install=i["install_id"] if isinstance(i.get("install_id"), str) else "",
            version=i["version"] if isinstance(i.get("version"), str) else "",
            doc=i["data"]
        )
        for i in items()
    ];
    s: dict[str, any] = json.loads(summary(uploads, MIN_INSTALLS, "2026-11-03T00:00:00Z"));
    with open("test/fixtures/benchmarks/expected.json") as f {
        want: dict[str, any] = json.load(f);
        assert s["format"] == "horizon-benchmark-summary" and s["version"] == 1;
        assert s["min_installs"] == want["min_installs"];
        assert s["groups"] == want["groups"], json.dumps(s["groups"]);
    }
}

test "only comparable runs count" {
    reasons = [r for r in [rejection(i["data"]) for i in items()] if r is not None];
    assert reasons == [
        "VSync on or unknown",
        "offscreen",
        "frame rate capped",
        "not every scene",
        "not the standard flight",
        "not a version 1 benchmark report"
    ], str(reasons);
}

test "medians and rounding" {
    assert median([3.0, 1.0, 2.0]) == 2.0 and median([4.0, 1.0, 2.0, 3.0]) == 2.5;
    assert median([math.nan]) is None;
    assert round_field("p95_ms", 3.46) == 3.5;
    assert round_field("world_ms", 4512.4) == 4512.0;
    assert round_field("avg_fps", 99.5) == 100.0;
}
