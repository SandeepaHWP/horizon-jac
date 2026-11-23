"""The anonymous "I'm playing" ping, and the live count it feeds. A ping holds a random session
ID, the release, the platform and whether a LAN or friends world is open: nothing else."""
import json;

"""How long a session counts after its last ping, in seconds: two pings."""
glob WINDOW_SECONDS: int = 120;

"""The platforms a ping may name, in this order everywhere."""
glob PLATFORMS: list[str] = ["linux", "macos", "windows", "other"];

"""The largest ping body the server reads."""
glob MAX_PING_BYTES: int = 512;

glob MAX_VERSION: int = 40;

"""One "I'm playing", as it is sent."""
obj Ping {
    has session: str,
        version: str,
        platform: str,
        lan: bool;
}

"""The live count, exact: sessions within the window, those with a world open, and per
version and platform."""
obj Count {
    has playing: int = 0,
        lan: int = 0,
        versions: dict[str, int] = {},
        platforms: dict[str, int] = {};
}

"""A ping from its JSON body, as serde reads it: the four fields, each of its type, and no other.
ValueError says what is wrong."""
def ping_of(body: bytes) -> Ping;

"""Why the server refuses this ping, or None."""
def ping_check(p: Ping) -> str | None;

"""A count as JSON, as serde_json writes the original's struct: fields in order, maps sorted."""
def count_json(c: Count) -> str;
