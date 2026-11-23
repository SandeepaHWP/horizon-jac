"""The api space: what the gate asks of the server's data. Every function here is untagged, so
only the project's own programs, holding the deployment's key, may call it; the gate is the one
that does. All graph work runs under one lock, as the original's store runs under one mutex; the
waits on GitHub and on the official server run outside it."""
import json;
import sys;
import threading;
import time;
import from stdjac { commit }

"""Answers to reuse, each with when it was made: aggregate by days, the benchmark summary, the
live count, the history by series and range, the vote counts."""
obj Caches {
    has totals: dict[int, tuple[float, str]] = {},
        summary: tuple[float, str] | None = None,
        live: tuple[float, str] | None = None,
        history: dict[str, tuple[float, str]] = {},
        votes: tuple[float, str] | None = None;
}

"""How long the aggregate and the summary are reused, in seconds."""
glob CACHE_FOR: float = 600.0;

"""How long a history answer is reused: a new sample comes each minute."""
glob HISTORY_FOR: float = 60.0;

"""How long the vote counts are reused."""
glob VOTES_FOR: float = 60.0;

"""The official server's count, at most: a larger number is a bad answer, not a count."""
glob MAX_OFFICIAL_PLAYERS: int = 1000000;

glob cfg: Config = config_from_env(),
     data_lock: threading.Lock = threading.Lock(),
     caches: Caches = Caches(),
     builds: Buckets = Buckets(),
     started: float = time.monotonic(),
     day_shift: int = 0,
     requeued: bool = False;

"""Today, in days since 1970 (a test moves it with `day_shift`)."""
def today -> int;

"""Now in seconds since 1970."""
def unix_now -> int;

"""Now as `YYYY-MM-DDTHH:MM:SSZ`."""
def utc_stamp -> str;

"""Reports a stopped server was filing are filed again: once, before the first data work."""
def ready;

"""Drops the cached public answers, after a deletion or an expiry."""
def forget_cached;

"""Checks the daily cap and keeps one decoded batch: 204, 429 over the cap, 503 when it could not
be kept."""
def take_batch(b: Batch) -> int;

"""Deletes everything an install sent: how many rows went."""
def forget_install(key: str) -> int;

"""The totals of the last `days` days, made again at most every ten minutes; None when making
them would pass the hour's build budget."""
def totals(days: int) -> str | None;

"""Players' benchmark groups, made again at most every ten minutes."""
def bench_summary -> str;

"""Raw benchmark reports after `after`, `limit` a page: the export's whole answer."""
def export_reports(after: int, limit: int) -> str;

"""Play sessions of the last `days` per machine, `limit` machines a page from `offset`."""
def export_hardware(days: int, offset: int, limit: int) -> str;

"""Records a checked ping; False when the table is full."""
def take_ping(p: Ping) -> bool;

"""How many play now, made again at most every eighth of the window."""
def live_now -> str;

"""The live count, or the official server's, over a range, made again at most every minute;
None for an unknown range or series."""
def history(series: str, range_name: str) -> str | None;

"""A vote, or one taken back: the item's count, or None when the item would be one too many."""
def take_vote(item: str, voter: str, up: bool) -> int | None;

"""Every item's count, made again at most every minute."""
def vote_counts -> str;

"""A checked report queued and opened as an issue: 201 with its issue, 202 when GitHub failed or
another request is filing it, 503 past the day's cap. `fields` is its JSON."""
def take_report(kind: str, fields: str, per_day: int) -> Reply;

"""The issue for a queued report of `kind`."""
def issue_for(kind: str, fields: dict[str, any]) -> Issue;

"""The day an install's newest row came in."""
def install_newest(key: str) -> int | None;

"""Upkeep: totals rebuilt, expired rows removed, idle sessions forgotten, old reports given up.
How many raw rows went."""
def maintain -> int;

"""Opens the reports whose issue isn't open yet; stops at the first failure."""
def file_pending;

"""Writes down the live count as this minute's, once the server has run a whole window."""
def record_players -> bool;

"""Asks the official server for its player count and writes it down as this minute's."""
def record_official -> bool;

"""Every ten minutes: the upkeep, then the reports GitHub refused before, on a thread of their
own so the server keeps reading requests while GitHub answers."""
@schedule(interval=600.0)
def upkeep;

"""Every minute: the live count, then the official server's on a thread of its own (a status
ping may wait seconds)."""
@schedule(interval=60.0)
def every_minute;
