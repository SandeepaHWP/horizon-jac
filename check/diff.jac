"""Runs the original horizon-telemetry-server and this port side by side with the same settings,
sends both the same requests, and compares what they answer: status, the headers a client reads,
and the body (JSON compared as values). Prints each difference and a summary; exits 1 on any.

    ORIGINAL=<path to the original's binary> dist/diff-linux-x86_64
"""
import gzip;
import http.client;
import json;
import os;
import shutil;
import subprocess;
import sys;
import tempfile;
import time;

"""The headers compared; the rest (date, content-length, connection) are the transport's."""
glob COMPARED: list[str] = [
    "content-type",
    "cache-control",
    "access-control-allow-origin",
    "access-control-allow-methods",
    "access-control-allow-headers",
    "access-control-max-age",
    "vary",
    "content-encoding",
    "allow"
];

"""One answer: its status, the compared headers, its body."""
obj Got {
    has status: int,
        headers: dict[str, str],
        body: bytes;
}

"""A running server: its processes, the port it answers on, and its data directory."""
obj Running {
    has name: str,
        procs: list[subprocess.Popen] = [],
        port: int = 0,
        data: str = "";
}

"""What a run found: requests compared and the differences, by scenario."""
obj Tally {
    has compared: int = 0,
        differences: list[str] = [],
        per_scenario: list[tuple[str, int, int]] = [];
}

"""Every server started and not yet stopped, so a failed run stops them too."""
glob started_servers: list[Running] = [];

glob tally: Tally = Tally(),
     scenario: str = "",
     scenario_start: tuple[int, int] = (0, 0);

"""Starts the original with `env` on `port`."""
def start_original(env: dict[str, str], port: int) -> Running;

"""Starts the port's api and gate with `env`, the gate on `port`."""
def start_port(env: dict[str, str], port: int) -> Running;

"""Waits until something answers on `port`."""
def wait_for(port: int);

"""Raises when something already listens on `port`: answers would come from it, not from the
server about to start."""
def free(port: int);

"""Raises when a process the server is made of has ended."""
def running(r: Running) -> Running;

"""Stops a server and removes its data."""
def stop(r: Running);

"""One request to one server."""
def ask(port: int, method: str, path: str, headers: dict[str, str], body: bytes) -> Got;

"""The same request to both; records any difference. The two answers, original first."""
def both(a: Running, b: Running, method: str, path: str, headers: dict[str, str] = {}, body: bytes = b"", loose: list[str] = []) -> tuple[Got, Got];

"""A body as a value to compare: JSON parsed (gunzipped first when it is), with the keys in
`loose` removed; else its text."""
def comparable(g: Got, loose: list[str]) -> any;

"""Lists inside a JSON value sorted where their order is the original's hash map's: ties the
original leaves in no order."""
def unordered(v: any) -> any;

"""Starts a named scenario; ends the last."""
def begin(name: str);

"""Ends the last scenario."""
def finish;

"""A batch of `items` from install `n`, encoded as the launcher sends it."""
def batch(n: int, items: list[Item]) -> bytes;

"""A perf item as the original's tests make it."""
def perf(gpu: str, distance: int) -> Item;

"""POSTs a batch to both."""
def post(a: Running, b: Running, n: int, items: list[Item], headers: dict[str, str] = {});

"""The settings every scenario starts from: generous limits, no official server."""
def base_env -> dict[str, str];

"""Runs every scenario."""
def run_all;

with entry {
    if os.environ.get("ORIGINAL", "") == "" {
        print("ORIGINAL must name the original server's binary", file=sys.stderr);
        sys.exit(2);
    }
    started = time.monotonic();
    try {
        run_all();
    } finally {
        for r in list(started_servers) {
            stop(r);
        }
    }
    for line in tally.differences {
        print("DIFF", line);
    }
    print();
    print("| Scenario | Requests | Differences |");
    print("|---|---|---|");
    for (name, n, d) in tally.per_scenario {
        print(f"| {name} | {n} | {d} |");
    }
    print(f"\n{tally.compared} requests compared, {len(tally.differences)} differences, in {time.monotonic() - started:.1f} s");
    sys.exit(1 if tally.differences else 0);
}
