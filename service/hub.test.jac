import from service.store { Hub, forget_lookups }

"""Starts again on an empty graph."""
def fresh {
    for h in [root.shared --> [?:Hub]] {
        remove(h);
    }
    forget_lookups();
    voted.clear();
    queued.clear();
    hub_loaded = False;
}

test "votes count once per browser and can be taken back" {
    fresh();
    a = "0b7c3c9e-3f0a-4d8e-9a39-4c1f5a6b7d21";
    b = "1b7c3c9e-3f0a-4d8e-9a39-4c1f5a6b7d21";
    assert vote("smooth-frames", a, True) == 1;
    assert vote("smooth-frames", a, True) == 1;
    assert vote("smooth-frames", b, True) == 2;
    assert vote("smooth-frames", a, False) == 1;
    assert votes_json() == '{"votes":{"smooth-frames":1}}';
    assert vote("smooth-frames", b, False) == 0;
    assert votes_json() == '{"votes":{}}';
}

test "a full table of items takes votes for known items only" {
    fresh();
    for n in range(MAX_ITEMS) {
        vote(f"item-{n}", "0b7c3c9e-3f0a-4d8e-9a39-4c1f5a6b7d21", True);
    }
    assert vote("one-more", "0b7c3c9e-3f0a-4d8e-9a39-4c1f5a6b7d21", True) is None;
    assert vote("item-3", "1b7c3c9e-3f0a-4d8e-9a39-4c1f5a6b7d21", True) == 2;
}

test "a report is queued once, claimed once, and expires" {
    fresh();
    (id, issue) = enqueue("report", 100, 99, '{"title":"x"}');
    assert issue is None and queued_on("report", 100) == 1;
    assert enqueue("report", 100, 99, '{"title":"x"}')
        == (id, None), "the same text is the same entry";
    assert claim(id) and not claim(id);
    release_claim(id);
    assert [q.id for q in unfiled(93)] == [id];
    assert claim(id);
    filed(id, "https://github.com/o/r/issues/1");
    assert enqueue("report", 100, 99, '{"title":"x"}') == (id, "https://github.com/o/r/issues/1");
    assert unfiled(93) == [];
    (old, _) = enqueue("game", 90, 89, '{"title":"y"}');
    assert expire_queue(10, 93) == 0 and queue()[old].state == "failed";
    assert expire_queue(95, 93) == 1 and old not in queue();
}
