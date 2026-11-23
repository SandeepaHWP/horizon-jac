import json;

"""The oracle's report vectors, one JSON object a line."""
def vectors -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    with open("test/report_vectors.jsonl") as f {
        for line in f {
            out.append(json.loads(line));
        }
    }
    return out;
}

test "the game's reports are checked and written as the original's are" {
    seen = 0;
    for v in vectors() {
        if v["case"] != "game" {
            continue;
        }
        seen += 1;
        got_err = "";
        fields: dict[str, any] = {};
        try {
            fields = game_fields(v["body"]);
        } except ValueError as e {
            got_err = str(e);
        }
        if "err" in v {
            assert got_err == v["err"], f"case {v['i']}: {got_err!r} != {v['err']!r}";
            continue;
        }
        assert got_err == "", f"case {v['i']}: refused: {got_err}";
        assert fields == v["fields"], f"case {v['i']}: {fields}";
        i = game_issue(fields);
        assert i.title == v["title"], f"case {v['i']}: {i.title!r}";
        assert i.body == v["issue"], f"case {v['i']}: body differs";
        assert i.labels == v["labels"], f"case {v['i']}: {i.labels}";
    }
    assert seen == 15;
}
