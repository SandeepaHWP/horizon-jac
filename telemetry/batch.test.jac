import json;
import from telemetry.payload { Item, Summary, Timings, item_of, item_json, validate }

"""The oracle's lines of one case."""
def vectors(which: str) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    with open("test/vectors.jsonl") as f {
        for line in f {
            v: dict[str, any] = json.loads(line);
            if v["case"] == which {
                out.append(v["out"]);
            }
        }
    }
    return out;
}

test "items read back and are written byte for byte as serde writes them" {
    for v in vectors("item_json") {
        text: str = v["json"];
        it = item_of(json.loads(text));
        assert item_json(it) == text, f"item {v['i']}:\n{item_json(it)}\n{text}";
        assert validate(it) == v["valid"];
    }
}

test "timings summarise as the original's do" {
    for v in vectors("timings") {
        t = Timings();
        seed: int = v["seed"];
        n: int = v["n"];
        for i in range(n) {
            x = ((i * 2654435761 + seed) % 4294967296) % 4000;
            t.record(f32(x) / f32(7.3) + f32(0.05));
        }
        s = t.summary();
        want: dict[str, any] = v["summary"];
        got = {
            "count": int(s.count),
            "p50_ms": float(s.p50_ms),
            "p95_ms": float(s.p95_ms),
            "p99_ms": float(s.p99_ms),
            "max_ms": float(s.max_ms),
            "buckets": [int(b) for b in s.buckets]
        };
        assert got == want, f"seed {seed}: {got} != {want}";
    }
}

test "batches decode or are refused as the original's are" {
    for v in vectors("batch") {
        body = bytes.fromhex(v["hex"]);
        ok = True;
        why = "";
        try {
            decode_batch(body);
        } except ValueError as e {
            ok = False;
            why = str(e);
        }
        assert ok == v["ok"], f"{v['name']}: {why}";
        if v["name"] in ["bad_id", "bad_schema", "no_items", "bomb"] {
            assert why == v["err"], f"{v['name']}: {why!r} != {v['err']!r}";
        }
    }
}
