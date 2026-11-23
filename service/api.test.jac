import http.server;
import socket;
import from stdjac { remove }
import from service.store { Hub, forget_lookups }
import from service.hub { voted, queued }
import from service.history { live_rows }
import from service.livetable { sessions }
import from service.issues { website_fields, fields_json }
import from telemetry.payload { Item, Bug, Crash, Source, Kind, Batch }
import from telemetry.batch { batch_json }
import from service.hub { hub_loaded }
import from service.game_report { game_fields }

"""What the stand-in GitHub was asked to open, whether it is down, and a gate that holds its
answer while a test looks at what else happens."""
glob opened: list[dict[str, any]] = [],
     github_down: bool = False,
     github_hold: threading.Event | None = None,
     github_started: threading.Event = threading.Event(),
     github_url: str = "";

"""Answers `POST /repos/<repo>/issues` as GitHub does, or 502 while it is down."""
class FakeGitHub(http.server.BaseHTTPRequestHandler) {
    def do_POST {
        body: dict[str, any] = json.loads(self.rfile.read(int(self.headers["Content-Length"])).decode());
        github_started.set();
        hold = github_hold;
        if hold is not None {
            hold.wait(10.0);
        }
        if github_down {
            self.send_response(502);
            self.send_header("Content-Length", "0");
            self.end_headers();
            return;
        }
        opened.append(body);
        answer = json.dumps({"html_url": f"https://github.com/horizon-rust/horizon/issues/{1000 + len(opened)}"}).encode();
        self.send_response(201);
        self.send_header("Content-Length", str(len(answer)));
        self.end_headers();
        self.wfile.write(answer);
    }

    override def log_message(format: str, *args: any) {}
}

"""Starts the stand-in GitHub once, and points the settings at it."""
def github {
    if github_url == "" {
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeGitHub);
        threading.Thread(target=srv.serve_forever, args=(0.5,), daemon=True).start();
        github_url = f"http://127.0.0.1:{srv.server_port}";
    }
    cfg.github_api = github_url;
    cfg.github_token = "a-token";
    cfg.github_repo = "horizon-rust/horizon";
}

"""Starts again: an empty graph, no caches, no sessions, the stand-in GitHub up and empty."""
def fresh {
    for h in [root.shared --> [?:Hub]] {
        remove(h);
    }
    forget_lookups();
    voted.clear();
    queued.clear();
    hub_loaded = False;
    live_rows.clear();
    sessions.clear();
    caches.totals.clear();
    caches.summary = None;
    caches.live = None;
    caches.history.clear();
    caches.votes = None;
    opened.clear();
    github_down = False;
    github_hold = None;
    day_shift = 0;
    github();
}

"""The website form's fields, checked as the gate checks them."""
def form(title: str) -> str {
    return fields_json(
        website_fields(
            {
                "title": title,
                "did": "Opened a new world\nWalked to the sea",
                "happened": "The water is black",
                "expected": "Blue water, as in vanilla",
                "version": "v0.2.57",
                "system": "Windows 11, Ryzen 5 5600, RX 6600",
                "website": ""
            }
        )
    );
}

"""A reply's JSON body."""
def body_of(r: Reply) -> dict[str, any] {
    return json.loads(r.body);
}

test "a report becomes an issue in the bug template" {
    fresh();
    r = take_report("report", form("Water is black on AMD"), 30);
    assert r.status == 201 and body_of(r)["issue"] == "https://github.com/horizon-rust/horizon/issues/1001", r.body;
    issue = opened.pop(0);
    assert issue["title"] == "Water is black on AMD" and issue["labels"] == ["bug", "from-website"];
    text: str = issue["body"];
    for line in [
        "> **What I did:**\n> Opened a new world\n> Walked to the sea",
        "> **What happened:**\n> The water is black",
        "> **What I expected:**\n> Blue water, as in vanilla",
        "> **Horizon version:** v0.2.57",
        "> **OS, CPU, GPU:** Windows 11, Ryzen 5 5600, RX 6600",
        "Reported on playhorizon.dev",
    ] {
        assert line in text, line;
    }
    again = take_report("report", form("Water is black on AMD"), 30);
    assert again.status == 201 and body_of(again)["issue"] == body_of(r)["issue"];
    assert opened == [], "a double click opens nothing";
}

test "a report GitHub refused is opened by the upkeep" {
    fresh();
    github_down = True;
    r = take_report("report", form("Crash when opening a chest"), 30);
    assert r.status == 202 and body_of(r)["issue"] is None;
    file_pending();
    assert len(opened) == 0;
    github_down = False;
    file_pending();
    assert len(opened) == 1;
    file_pending();
    assert len(opened) == 1, "opened once";
}

test "reports are capped per day" {
    fresh();
    for n in range(3) {
        assert take_report("report", form(f"Bug number {n}"), 3).status == 201;
    }
    assert take_report("report", form("Bug number 9"), 3).status == 503;
    day_shift = 1;
    assert take_report("report", form("Bug number 9"), 3).status == 201, "a new day";
}

test "old entries go and reports never opened are given up" {
    fresh();
    github_down = True;
    r = take_report("report", form("Crash when opening a chest"), 30);
    assert body_of(r)["id"] > 0;
    day_shift = 8;
    maintain();
    github_down = False;
    file_pending();
    assert opened == [], "past a week a report is given up";
}

test "a report sent twice while GitHub is slow opens one issue" {
    fresh();
    hold = threading.Event();
    github_hold = hold;
    github_started.clear();
    first: list[Reply] = [];
    def send_first {
        first.append(take_report("report", form("Crash when opening a chest"), 30));
    }
    t = threading.Thread(target=send_first);
    t.start();
    assert github_started.wait(10.0);
    second = take_report("report", form("Crash when opening a chest"), 30);
    assert second.status == 202 and body_of(second)["issue"] is None;
    file_pending();
    hold.set();
    t.join();
    assert first[0].status == 201;
    assert body_of(second)["id"] == body_of(first[0])["id"];
    assert len(opened) == 1, "one issue for one report";
    again = take_report("report", form("Crash when opening a chest"), 30);
    assert again.status == 201 and body_of(again)["issue"] == body_of(first[0])["issue"];
}

test "a game report opens an issue in the game's template" {
    fresh();
    fields = game_fields(
        {
            "category": "bug",
            "title": "Water is black",
            "happened": "The water turned black",
            "version": "v0.4.2",
            "system": [["GPU", "RX 6600"]],
            "area": "rendering"
        }
    );
    r = take_report(KIND, fields_json(fields), 20);
    assert r.status == 201, r.body;
    assert opened[0]["labels"] == ["from-game", "bug", "rendering"];
}

test "the recorder waits a window, then writes the exact count" {
    fresh();
    cfg.live_window = 1;
    started = time.monotonic();
    assert not record_players(), "just started: games haven't all pinged yet";
    time.sleep(1.1);
    for n in range(3) {
        assert take_ping(Ping(session=f"{n:032x}", version="0.2.0", platform="linux", lan=n == 0));
    }
    assert record_players();
    day: dict[str, any] = json.loads(history("players", "24h"));
    assert day["peak"]["playing"] == 3 and day["platforms"]["linux"] == 3.0;
    cfg.live_window = 120;
}

"""A stand-in official server: answers one status ping with `answer`. Its address."""
def official_server(answer: str) -> str {
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    listener.bind(("127.0.0.1", 0));
    listener.listen(1);
    port: int = listener.getsockname()[1];
    def serve {
        (conn, _) = listener.accept();
        conn.recv(256);
        text = answer.encode();
        packet = bytes([0, len(text)]) + text;
        conn.sendall(bytes([len(packet)]) + packet);
        conn.close();
        listener.close();
    }
    threading.Thread(target=serve, daemon=True).start();
    return f"127.0.0.1:{port}";
}

test "the official server's count is pinged and served apart" {
    fresh();
    cfg.official_server = official_server('{"players":{"online":4,"max":50}}');
    assert record_official();
    day: dict[str, any] = json.loads(history("official", "24h"));
    assert day["source"] == "official" and day["peak"]["playing"] == 4;
    players: dict[str, any] = json.loads(history("players", "24h"));
    assert players["source"] == "players" and players["peak"] is None;
    assert history("lan", "24h") == "";
    cfg.official_server = "127.0.0.1:1";
    assert not record_official(), "nobody at the address: nothing is written";
}

test "an impossible official count is not written" {
    fresh();
    cfg.official_server = official_server('{"players":{"online":18446744073709551615,"max":50}}');
    assert not record_official();
    assert json.loads(history("official", "24h"))["peak"] is None;
}

test "an install's daily cap starts again the next day" {
    fresh();
    cfg.items_per_day = 3;
    def bugs(n: int) -> str {
        it = Item(day=u32(1), source=Source.GAME, version="v1", kind=Kind.BUG, bug=Bug(text="hi"));
        return batch_json(Batch(schema=u32(1), install_id="0" * 32, items=[it] * n));
    }
    assert take_batch(bugs(2)) == 204;
    assert take_batch(bugs(2)) == 429;
    assert take_batch(bugs(1)) == 204;
    day_shift = 1;
    assert take_batch(bugs(3)) == 204;
    cfg.items_per_day = 100;
}

test "raw rows expire in the upkeep and the totals stay" {
    fresh();
    cfg.min_install_days = 1;
    it = Item(day=u32(1), source=Source.GAME, version="v1", kind=Kind.CRASH, crash=Crash());
    assert take_batch(batch_json(Batch(schema=u32(1), install_id="0" * 32, items=[it]))) == 204;
    assert install_newest("0" * 32) == today();
    day_shift = 179;
    assert maintain() == 0, "still within retention";
    day_shift = 181;
    assert maintain() == 1;
    assert install_newest("0" * 32) is None;
    cfg.min_install_days = 5;
}
