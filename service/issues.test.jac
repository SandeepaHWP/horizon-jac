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

test "people's text mentions and references nothing" {
    text = neutralise(
        "@octocat see #12 and https://github.com/a/b/issues/3 <img src=x> `x` Fixes it"
    );
    assert "@o" not in text and "#1" not in text and "github.com/" not in text;
    assert "<" not in text and "`" not in text;
    assert "F​ixes" in text;
    assert neutralise("closet fixture") == "closet fixture";
}

test "GH references link nothing either" {
    assert neutralise("see GH-12") == "see GH​-12";
    assert neutralise("gh-7, (Gh-8)") == "gh​-7, (Gh​-8)";
    assert neutralise("high-5 GH-pages laugh-1 aGH-3") == "high-5 GH-pages laugh-1 aGH-3";
}

test "a report reads as the template" {
    i = website_issue({
        "title": "Water is black\non AMD",
        "did": "Opened a world",
        "happened": "Black water",
        "expected": "Blue water",
        "system": "Windows 11, RX 6600",
        "name": "steve_",
    });
    assert i.title == "Water is black on AMD";
    assert i.body.startswith("> **What I did:**\n> Opened a world\n> **What happened:**");
    assert "> **Horizon version:** not given\n> **OS, CPU, GPU:** Windows 11, RX 6600" in i.body;
    assert "Reported on playhorizon.dev by **steve**" in i.body;
    assert i.labels == ["bug", "from-website"];
}

test "links and images are not live markdown" {
    for text in [
        "[click](https://evil.example/login)",
        "![x](https://evil.example/p.png)",
        "[a][b]\n\n[b]: https://evil.example",
        "![a][b]\n\n[b]: https://evil.example",
        "[a]\n\n[a]: https://evil.example",
    ] {
        out = neutralise(text);
        assert "](" not in out and "][" not in out and "]:" not in out, out;
        assert neutralise(out) == out, "idempotent";
        assert out.replace("​", "") == text, "readable";
    }
}

test "the issue body has no live link and keeps bare URLs" {
    i = website_issue({
        "did": "![x](https://evil.example/p.png) join play.example.org:25565",
        "title": "[t](https://evil.example)",
    });
    assert "](" not in i.body and "](" not in i.title;
    assert "play.example.org:25565" in i.body;
}

test "the website's reports are written as the original's are" {
    for v in vectors() {
        if v["case"] == "website" {
            i = website_issue(v["fields"]);
            assert (i.title, i.body, i.labels)
                == (
                    v["title"],
                    v["issue"],
                    v["labels"],
                ), f"case {v['i']}:\n{i.body}\n---\n{v['issue']}";
        } elif v["case"] == "neutralise" {
            assert neutralise(v["in"]) == v["out"], f"{neutralise(v['in'])!r} != {v['out']!r}";
        }
    }
}
