"""A batch on the wire: an install's items as one JSON object, zstd-compressed. The server
inflates it with `decode`, which bounds what it inflates."""
import json;
import compression.zstd;

"""A batch on the wire, compressed, at most."""
glob MAX_COMPRESSED: int = 262144;

"""A batch's JSON, inflated, at most."""
glob MAX_JSON: int = 1048576;

"""Items in one batch, at most."""
glob MAX_ITEMS: int = 64;

"""The payload format this server reads."""
glob SCHEMA: int = 1;

"""Inflates and checks a batch: its size before and after, its schema and install ID, and every
item. ValueError says what is wrong."""
def decode_batch(body: bytes) -> Batch;

"""A batch as the launcher sends it: compact JSON, zstd-compressed."""
def encode_batch(b: Batch) -> bytes;

"""A batch's JSON, as serde_json writes it."""
def batch_json(b: Batch) -> str;
