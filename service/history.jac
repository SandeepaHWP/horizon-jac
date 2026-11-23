"""The live count over time, for playhorizon.dev/stats. Once a minute the server writes down how
many play, how many have a world open, and how many per platform: totals only, never a session.
A minute is kept 7 days, an hour 90, a day for good; the official server's count is a series of
its own, kept the same way."""
import from stdjac { remove }

glob HOUR: int = 3600,
     DAY_SECONDS: int = 86400;

"""One minute's count, as it is stored: per platform in `PLATFORMS`' order."""
obj Sample {
    has playing: int = 0,
        lan: int = 0,
        platforms: list[int] = [0, 0, 0, 0];
}

"""One minute's sample."""
node Minute {
    has t: int,
        playing: int,
        lan: int,
        platforms: list[int];
}

"""An hour's or a day's minutes rolled up: how many, their sum and peak (with its minute), and
the sums per platform."""
node Roll {
    has t: int,
        samples: int = 0,
        peak: int = 0,
        peak_at: int = 0,
        total: int = 0,
        lan_peak: int = 0,
        lan_sum: int = 0,
        platform_sums: list[int] = [0, 0, 0, 0];
}

"""A row as the history reads it: a minute is one sample."""
obj Row {
    has t: int,
        samples: int,
        total: int,
        peak: int,
        peak_at: int,
        platform_sums: list[int];
}

"""A sample from a live count."""
def sample_of(c: Count) -> Sample;

"""Writes down `sample` as `series`' count of the minute holding `unix`, and adds it to its hour
and day. False, and nothing changes, when that minute has one already."""
def record_live(series: str, unix: int, sample: Sample) -> bool;

"""Removes minutes older than `minute_days` and hours older than `hour_days` before `now`, in
every series. Days stay. How many went."""
def prune_live(now: int, minute_days: int, hour_days: int) -> int;

"""`series` over `range` up to `now`, as `GET /v1/live/history` answers it; None for an unknown
range or series."""
def live_history(series: str, range_name: str, now: int) -> str | None;

"""The rows of one series' table (`minute`, `hour` or `day`), by their start."""
def rows_of(series: str, table: str) -> dict[int, any];

"""Every row of one series' table as the history reads it."""
def rows(series: str, table: str) -> list[Row];

glob live_rows: dict[str, dict[int, any]] = {};
