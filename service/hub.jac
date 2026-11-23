"""The hub's votes: a thumbs-up on a roadmap item at playhorizon.dev/hub, one per browser (a random
id the page makes), and the queue of bug reports the hub and the game send. Kept: an item id and
the browser's id per vote; a report as its text. Never an address."""
import time;
import from stdjac { remove }

"""Items with votes, at most: a vote for a new id past this is refused."""
glob MAX_ITEMS: int = 1000;

"""Days the upkeep keeps trying to open a report's issue."""
glob RETRY_DAYS: int = 7;

"""A roadmap item and the browsers that voted for it. An item with no votes is no node."""
node VotedItem {
    has item: str,
        voters: list[str] = [];
}

"""A report waiting for, or holding, its issue. `state` is `new`, `filing`, `filed` or `failed`."""
node Queued {
    has id: int,
        kind: str,
        day: int,
        created: str,
        state: str = "new",
        issue: str = "",
        body: str;
}

"""A roadmap item id's shape: lowercase words joined by dashes, at most 48 characters."""
def item_id(id: str) -> bool;

"""A voter id's shape: what `crypto.randomUUID()` and the like make."""
def voter_id(id: str) -> bool;

"""Adds or takes back a vote; the item's count after it. None when the item would be one too many."""
def vote(item: str, voter: str, up: bool) -> int | None;

"""Every item's count, as `{"votes": {...}}`."""
def votes_json -> str;

"""Every queued report, by id."""
def queue -> dict[int, Queued];

"""How many entries of `kind` came in on `day`."""
def queued_on(kind: str, day: int) -> int;

"""Queues an entry: its id, and its issue when the same text came in since `since` and was opened."""
def enqueue(kind: str, day: int, since: int, body: str) -> tuple[int, str | None];

"""Reports whose issue isn't open yet, from `since` on, oldest first."""
def unfiled(since: int) -> list[Queued];

"""Takes a report for filing: true for exactly one caller, while it is `new`."""
def claim(id: int) -> bool;

"""Gives a claimed report back after GitHub refused it."""
def release_claim(id: int);

"""Marks a report as opened: `issue` is its URL."""
def filed(id: int, issue: str);

"""Gives up reports from before `retry_from` that never got an issue; entries before `oldest_day`
go. How many went."""
def expire_queue(oldest_day: int, retry_from: int) -> int;

"""Reports a stopped server was filing are filed again."""
def requeue_filing;

"""Now as `YYYY-MM-DDTHH:MM:SSZ`, as the original writes a report's time."""
def utc_now -> str;

glob voted: dict[str, VotedItem] = {},
     queued: dict[int, Queued] = {},
     hub_loaded: bool = False;

"""Loads the votes and the queue from the graph, the first time."""
def load_hub;
