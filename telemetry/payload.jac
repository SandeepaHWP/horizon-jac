"""What an item holds, read and written as horizon-telemetry's serde types are."""
import json;
import math;
import from stdjac { decode, CodecError }

"""The upper edges of a summary's buckets in milliseconds; the last bucket has none."""
glob BUCKET_EDGES_MS: list[float] = [
    4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.7, 20.0, 25.0, 33.3, 50.0, 100.0, 250.0,
];

"""A summary's bucket count: one past the edges."""
glob BUCKETS: int = 14;

"""The four kinds of data a player can allow."""
enum Kind {
    PERF = 0,
    CRASH = 1,
    BUG = 2,
    BENCHMARK = 3,
}

"""What made an item."""
enum Source {
    LAUNCHER,
    GAME,
}

"""A screen: its size in physical pixels, refresh rate and scale."""
obj Display {
    has width: u32 = u32(0),
        height: u32 = u32(0),
        refresh_hz: u32 = u32(0),
        scale: f32 = f32(0.0);
}

"""The machine, as coarse as is useful. Empty or zero: not known."""
obj System {
    has os: str = "",
        os_version: str = "",
        arch: str = "",
        cpu: str = "",
        threads: u16 = u16(0),
        cores: u16 = u16(0),
        cpu_base_mhz: u32 = u32(0),
        cpu_boost_mhz: u32 = u32(0),
        ram_gb: u16 = u16(0),
        gpu: str = "",
        gpu_vendor: str = "",
        gpu_kind: str = "",
        vram_mb: u32 = u32(0),
        driver: str = "",
        backend: str = "",
        storage: str = "",
        display: Display | None = None,
        power: str = "",
        form: str = "";
}

"""The settings that change performance."""
obj Settings {
    has render_distance: u8 = u8(0),
        simulation_distance: u8 = u8(0),
        max_fps: u16 = u16(0),
        vsync: bool = False,
        fullscreen: bool = False,
        graphics: str = "";
}

"""Durations at a glance: percentiles and a count per bucket."""
obj Summary {
    has count: u64 = u64(0),
        p50_ms: f32 = f32(0.0),
        p95_ms: f32 = f32(0.0),
        p99_ms: f32 = f32(0.0),
        max_ms: f32 = f32(0.0),
        buckets: list[u32] = [];
}

"""Slow frames whose longest step was one span."""
obj SlowFrames {
    has span: str = "",
        frames: u32 = u32(0),
        frame_max_ms: f32 = f32(0.0),
        span_max_ms: f32 = f32(0.0);
}

glob SLOW_MAX_SPANS: int = 16,
     SLOW_MAX_NAME: int = 64,
     SLOW_OTHER: str = "other";

"""One play session's performance."""
obj Perf {
    has system: System = System(),
        settings: Settings = Settings(),
        seconds: u32 = u32(0),
        frames: Summary = Summary(),
        ticks: Summary | None = None,
        peak_ram_mb: u32 = u32(0),
        to_title_ms: u32 | None = None,
        to_core_ms: u32 | None = None,
        to_rest_ms: u32 | None = None,
        to_world_ms: u32 | None = None,
        slow_frames: list[SlowFrames] = [];
}

"""A crash, scrubbed."""
obj Crash {
    has system: System = System(),
        error: str = "",
        stack: str = "",
        thread: str = "",
        details: list[tuple[str, str]] = [];
}

"""A bug report the player wrote."""
obj Bug {
    has system: System = System(),
        text: str = "",
        log: str | None = None;
}

glob BUG_MAX_TEXT: int = 4000;

"""One item: its day, maker, release and payload. Exactly one payload field is set, by `kind`;
a benchmark report is kept as its JSON text, as it is any JSON object."""
obj Item {
    has day: u32,
        source: Source,
        version: str,
        kind: Kind,
        perf: Perf | None = None,
        crash: Crash | None = None,
        bug: Bug | None = None,
        benchmark: str = "";
}

"""An install's items on the wire."""
obj Batch {
    has schema: u32,
        install_id: str,
        items: list[Item];
}

"""A kind's name, as the JSON has it."""
def kind_name(k: Kind) -> str;

"""The kind of a name, or None."""
def kind_of(name: str) -> Kind | None;

"""The largest an item of this kind may be, as JSON."""
def max_bytes(k: Kind) -> int;

"""Thirty-two lowercase hex digits."""
def is_install_id(id: str) -> bool;

"""`v` decoded as a `T`, or ValueError with what is wrong."""
def decoded[T](v: any, at: str) -> T;

"""An item from its JSON value, checked for shape (not for size: `validate` does that)."""
def item_of(v: any) -> Item;

"""A batch from its JSON text's value."""
def batch_of(v: any) -> Batch;

"""Why the server refuses this item, or None: its size, its version, its text."""
def validate(it: Item) -> str | None;

"""A JSON value as serde_json writes a `Value`: compact, keys sorted, non-ASCII as it is."""
def value_json(v: any) -> str;

"""A string as JSON."""
def jstr(s: str) -> str;

"""An f32 as serde_json writes it: its shortest form, with `.0` on a whole number."""
def f32_json(x: f32) -> str;

def display_json(d: Display) -> str;

def system_json(s: System) -> str;

def settings_json(s: Settings) -> str;

def summary_json(s: Summary) -> str;

def slow_json(s: SlowFrames) -> str;

def opt_json(name: str, v: u32 | None) -> str;

def perf_json(p: Perf) -> str;

def crash_json(c: Crash) -> str;

def bug_json(b: Bug) -> str;

"""An item's payload as JSON, as serde_json writes it."""
def data_json(it: Item) -> str;

"""An item as JSON, as serde_json writes it: its size is what `validate` measures."""
def item_json(it: Item) -> str;

"""Counts a slow frame of `frame_ms` whose longest span was `span` (`""`: none) for `span_ms`,
in a session's list; past the cap, new spans share `other`."""
def record_slow(spans: list[SlowFrames], frame_ms: f32, span: str, span_ms: f32);

"""Records durations in tenths of a millisecond up to 500 ms, for percentiles finer than the
buckets."""
obj Timings {
    has tenths: list[int] = [0] * 5001,
        count: int = 0,
        max_ms: f32 = f32(0.0);

    """Counts one duration; a negative or non-finite one is left out."""
    def record(ms: f32);

    """The duration under which a fraction `p` of them fell, to the tenth of a millisecond."""
    def percentile(p: float) -> f32;

    """The percentiles and bucket counts."""
    def summary -> Summary;
}

"""An f32 rounded to the tenth, as Rust's `(ms * 10.0).round() / 10.0` on an f32."""
def tenth32(ms: f32) -> f32;
