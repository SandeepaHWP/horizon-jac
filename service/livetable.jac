"""Who is playing now, from the games' pings. In memory only: a session ID, when it last pinged,
its version, platform and LAN flag. Nothing is written down, so a restart starts the count again;
it is whole again a minute later."""

"""Versions listed by name in a count; the rest are summed under `other`."""
glob VERSIONS_SHOWN: int = 12;

"""One session's last ping."""
obj Seen {
    has at: float,
        version: str,
        platform: int,
        lan: bool;
}

glob sessions: dict[str, Seen] = {};

"""Records a checked ping as seen at `now` (seconds). False when the table is full and the
session is new."""
def live_ping(p: Ping, now: float, window: int, most: int) -> bool;

"""Drops the sessions whose last ping is older than the window."""
def live_forget(now: float, window: int);

"""Who is playing at `now`, exactly."""
def live_count(now: float, window: int) -> Count;
