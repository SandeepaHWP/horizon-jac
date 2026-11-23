"""Players' benchmark uploads, grouped for the website's Benchmarks page: the same rules as the
website's `scripts/benchmarks.mjs`, held to the same fixtures. A group is published only with
three different installs; each install counts once, the median of its runs first."""
import math;

glob FORMAT: str = "horizon-benchmark-summary",
     MIN_INSTALLS: int = 3,
     SCENES: list[str] = ["village", "forest", "ocean", "mountain"],
     FIELDS: list[str] = [
         "avg_fps",
         "low_1pct_fps",
         "p95_ms",
         "world_ms",
         "chunk_load_ms",
         "rss_peak_mb",
         "rss_steady_mb"
     ];

"""One stored upload: who sent it (only to count installs), the release, and the report."""
obj Upload {
    has install: str,
        version: str,
        doc: any;
}

"""One group's uploads as they are read: each install's runs, the installs per class, the
reports and releases."""
obj Group {
    has installs: dict[str, list[list[float | None]]] = {},
        classes: list[dict[str, set[str]]] = [{}, {}, {}, {}, {}],
        reports: int = 0,
        versions: set[str] = set();
}

"""Why a report can't be compared with the others, or None when it can."""
def rejection(doc: any) -> str | None;

"""The median of the finite values, or None."""
def median(xs: list[float]) -> float | None;

"""fps to integers, milliseconds to a tenth under 10 and to integers above, megabytes to
integers."""
def round_field(field: str, x: float) -> float;

"""Players' groups of at least `min_installs` installs, as JSON values."""
def groups(uploads: list[Upload], min_installs: int) -> list[dict[str, any]];

"""The whole answer, as JSON text; `generated` is an RFC 3339 UTC time."""
def summary(uploads: list[Upload], min_installs: int, generated: str) -> str;

"""Per dimension, the classes with at least `min_installs` installs, most first."""
def breakdowns(classes: list[dict[str, set[str]]], min_installs: int) -> dict[str, any];

"""'Intel(R) Core(TM) i7' as 'Intel Core i7', spaces collapsed."""
def trim(s: str) -> str;

"""`horizon` or `vanilla` for a report's app, or None."""
def game(app: any) -> str | None;

"""A report's seven figures: frame figures averaged over every flight, the rest from its
metrics."""
def figures(doc: any) -> list[float | None];

"""A whole number as an int, as JavaScript writes it; else the float."""
def number(x: float) -> any;
