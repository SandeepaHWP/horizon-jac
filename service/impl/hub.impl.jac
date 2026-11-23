impl load_hub {
    if hub_loaded {
        return;
    }
    for v in [hub("votes") --> [?:VotedItem]] {
        voted[v.item] = v;
    }
    for q in [hub("queue") --> [?:Queued]] {
        queued[q.id] = q;
    }
    hub_loaded = True;
}

impl vote(item: str, voter: str, up: bool) -> int | None {
    load_hub();
    v = voted.get(item);
    if up {
        if v is None and len(voted) >= MAX_ITEMS {
            return None;
        }
        if v is None {
            v = VotedItem(item=item);
            hub("votes") ++> v;
            voted[item] = v;
        }
        if voter not in v.voters {
            v.voters = v.voters + [voter];
        }
        return len(v.voters);
    }
    if v is None {
        return 0;
    }
    v.voters = [x for x in v.voters if x != voter];
    n = len(v.voters);
    if n == 0 {
        remove(v);
        del voted[item];
    }
    return n;
}

impl votes_json -> str {
    load_hub();
    return dumps({"votes": {item: len(v.voters) for (item, v) in voted.items()}});
}

impl queue -> dict[int, Queued] {
    load_hub();
    return queued;
}

impl queued_on(kind: str, day: int) -> int {
    return len([q for q in queue().values() if q.kind == kind and q.day == day]);
}

impl utc_now -> str {
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime());
}

impl enqueue(kind: str, day: int, since: int, body: str) -> tuple[int, str | None] {
    for id in sorted(queue().keys()) {
        q = queued[id];
        if q.kind == kind and q.body == body and q.day >= since {
            return (q.id, q.issue if q.issue != "" else None);
        }
    }
    c = counters();
    q = Queued(id=c.next_queue, kind=kind, day=day, created=utc_now(), body=body);
    c.next_queue += 1;
    hub("queue") ++> q;
    queued[q.id] = q;
    return (q.id, None);
}

impl unfiled(since: int) -> list[Queued] {
    return [
        queued[id]
        for id in sorted(queue().keys())
        if queued[id].kind in ["report", "game"] and queued[id].state == "new" and queued[id].day >= since
    ];
}

impl claim(id: int) -> bool {
    q = queue().get(id);
    if q is None or q.state != "new" {
        return False;
    }
    q.state = "filing";
    return True;
}

impl release_claim(id: int) {
    q = queue().get(id);
    if q is not None and q.state == "filing" {
        q.state = "new";
    }
}

impl filed(id: int, issue: str) {
    q = queue().get(id);
    if q is not None {
        q.state = "filed";
        q.issue = issue;
    }
}

impl expire_queue(oldest_day: int, retry_from: int) -> int {
    removed = 0;
    for id in sorted(queue().keys()) {
        q = queued[id];
        if q.kind in ["report", "game"] and q.state == "new" and q.day < retry_from {
            q.state = "failed";
        }
        if q.day < oldest_day {
            remove(q);
            del queued[id];
            removed += 1;
        }
    }
    return removed;
}

impl requeue_filing {
    for q in queue().values() {
        if q.state == "filing" {
            q.state = "new";
        }
    }
}
