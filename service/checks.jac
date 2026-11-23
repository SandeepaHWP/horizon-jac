"""The shapes of the hub's ids, checked where a request comes in."""

"""A roadmap item id's shape: lowercase words joined by dashes, at most 48 characters."""
def item_id(id: str) -> bool;

"""A voter id's shape: what `crypto.randomUUID()` and the like make."""
def voter_id(id: str) -> bool;
