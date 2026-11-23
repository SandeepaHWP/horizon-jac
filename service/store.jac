"""What the server keeps of the batches it takes, as a graph under the shared root.

Each install and each day is a node; a play session and a report hang off both, so an install is
deleted, and a day's totals are rebuilt, by following edges. A machine description is a node of its
own, kept once however many sessions ran on it. A day keeps its totals after its raw sessions
expire. Days are the day the server received an item (days since 1970, UTC). The sender's address is
never kept."""
import json;
import struct;
import time;
import compression.zstd;
import from stdjac { remove }

"""The summary bucket count: the edges and one more."""
glob BUCKET_COUNT: int = 14;

"""A collection's entry point: every node of one kind hangs off its hub, so reading one kind never
loads the others."""
node Hub {
    has name: str;
}

"""An install: its 32 hex digits, never shown."""
node Install {
    has key: str;
}

"""One day's raw rows hang off it; its totals stay after they expire."""
node Day {
    has day: int,
        dirty: bool = False,
        totals: list[DayGroup] = [];
}

"""A day's totals for one version, OS, GPU maker and render distance."""
obj DayGroup {
    has version: str,
        os: str,
        gpu_vendor: str,
        render_distance: int,
        sessions: int = 0,
        installs: int = 0,
        seconds: int = 0,
        buckets: list[int] = [],
        p50_sum: float = 0.0,
        p99_sum: float = 0.0;
}

"""A distinct machine description: the nine fields the totals use, the rest as JSON in `extra`.
`uses` counts the sessions and reports that point at it, so the last one to go takes it."""
node Machine {
    has key: str,
        os: str,
        os_version: str,
        arch: str,
        cpu: str,
        threads: int,
        ram_gb: int,
        gpu: str,
        driver: str,
        backend: str,
        extra: str,
        uses: int = 0;
}

"""One play session, in fields. `frames` and `ticks` are summaries packed in 80 bytes."""
node Session {
    has install: str,
        day: int,
        version: str,
        machine: str,
        render_distance: int,
        simulation_distance: int,
        max_fps: int,
        vsync: bool,
        fullscreen: bool,
        graphics: str,
        seconds: int,
        frames: bytes,
        ticks: bytes | None = None,
        peak_ram_mb: int = 0,
        to_title_ms: int | None = None,
        to_world_ms: int | None = None,
        slow_frames: str | None = None;
}

"""A crash or bug report or a benchmark upload; its data is zstd-compressed JSON. `id` orders
reports as they came, for the export's pages."""
node Report {
    has id: int,
        install: str,
        day: int,
        kind: int,
        version: str,
        machine: str = "",
        body: bytes = b"";
}

"""One release and step's slow frames over a window."""
obj StepTotals {
    has frames: int = 0,
        sessions: int = 0,
        installs: set[str] = set(),
        frame_max_ms: float = 0.0,
        span_max_ms: float = 0.0;
}

"""One hardware class's sessions over a window."""
obj ClassTotals {
    has installs: set[str] = set(),
        sessions: int = 0,
        seconds: int = 0,
        p50_sum: float = 0.0,
        p99_sum: float = 0.0;
}

"""One machine description's sessions over a window, for the export."""
obj MachineTotals {
    has description: dict[str, any],
        installs: set[str] = set(),
        sessions: int = 0,
        seconds: int = 0,
        p50_sum: float = 0.0,
        p99_sum: float = 0.0,
        buckets: list[int] = [],
        peak_ram_mb: int = 0;
}

"""Counters that outlive a restart."""
node Counters {
    has next_report: int = 1,
        next_queue: int = 1;
}

"""The hub of a collection under the shared root, made the first time it is asked for."""
def hub(name: str) -> Hub;

"""The counters node, made the first time it is asked for."""
def counters -> Counters;

"""The install with this key, if it has sent anything."""
def install_node(key: str) -> Install | None;

"""The day node, made when `make` and it is missing."""
def day_node(day: int, make: bool) -> Day | None;

"""Every day node, oldest first."""
def all_days -> list[Day];

"""The machine a session or report points at."""
def machine_of(id: str) -> Machine | None;

"""A summary in 80 bytes: the count, four percentiles, then the 14 buckets, little-endian."""
def pack(s: Summary) -> bytes;

"""A packed summary, or None for bytes of another length."""
def unpack(raw: bytes) -> Summary | None;

"""The GPU's maker, the one GPU detail the public totals group by."""
def gpu_vendor(gpu: str) -> str;

"""The machine node for a description, made the first time it is seen."""
def machine_for(s: System) -> Machine;

"""How many items an install has sent on `day`."""
def count_on(key: str, day: int) -> int;

"""Keeps a decoded batch, received on `day`."""
def insert(b: Batch, day: int);

"""Deletes everything an install sent; the days it touched get their totals rebuilt. How many rows
went."""
def delete_install(key: str) -> int;

"""One fewer row points at this machine; the last one to go takes it."""
def release(id: str);

"""Removes raw rows received before `oldest_day`; the daily totals stay. How many rows went."""
def expire(oldest_day: int) -> int;

"""Rebuilds the totals of every day marked changed."""
def rebuild_dirty;

"""Rebuilds one day's totals from its sessions."""
def rebuild_day(d: Day);

"""The anonymous totals for the days `start..=end`, groups with fewer than `k` install-days left
out, as JSON text."""
def aggregate(start: int, end: int, k: int) -> str;

"""What froze in `start..=end`, per release and step, steps seen by at least `k` installs."""
def slow_frames(start: int, end: int, k: int) -> list[dict[str, any]];

"""Sessions in `start..=end` per hardware class, classes with three installs at least."""
def breakdowns(start: int, end: int) -> dict[str, any];

"""Every benchmark upload received since `from_day`, with its install and release."""
def benchmark_uploads(from_day: int) -> list[Upload];

"""The day an install's newest row came in, if it has any left."""
def newest_day(key: str) -> int | None;

"""Benchmark reports with an id above `after`, oldest first, at most `limit`."""
def export_benchmarks(after: int, limit: int) -> list[dict[str, any]];

"""Play sessions in `start..=end` per machine description, the busiest first."""
def export_machines(start: int, end: int) -> list[dict[str, any]];

"""A stored body back as its JSON value."""
def inflate(body: bytes) -> any;

"""The sessions of the days `start..=end`."""
def sessions_in(start: int, end: int) -> list[Session];

"""The machine fields after the first nine, as `extra` keeps them."""
def extra_json(s: System) -> str;

"""Forgets the in-memory lookups, for a test that starts again on a new graph."""
def forget_lookups;

"""Lookups from key to node, built from the hubs as they are first needed: the graph has no index
of its own."""
glob installs_by_key: dict[str, Install] = {},
     days_by_day: dict[int, Day] = {},
     machines_by_key: dict[str, Machine] = {},
     machines_by_id: dict[str, Machine] = {},
     hubs: dict[str, Hub] = {},
     loaded: set[str] = set();
