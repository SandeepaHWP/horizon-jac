"""Token buckets: `per_hour` tokens an hour per key, bursts of a tenth of it. Kept in memory only,
never stored or logged."""
import time;

"""Most keys one map holds (a few tens of bytes each)."""
glob MAX_BUCKETS: int = 200000;

"""How often a full map looks over all its buckets for ones that have refilled, in seconds."""
glob SWEEP_EVERY: float = 1.0;

"""A map of buckets by key, each its tokens and when they were counted, and when a full map last
looked for refilled ones."""
obj Buckets {
    has tokens: dict[str, float] = {},
        at: dict[str, float] = {},
        swept: float | None = None;

    """Takes a token for `key`; False when it has none left. A full map drops the buckets that
    have refilled and, if that frees nothing, turns new keys away."""
    def take(per_hour: float, key: str, most: int = MAX_BUCKETS) -> bool;

    """Forgets the buckets not touched for an hour."""
    def forget_idle;
}
