"""The gate's answers: the original server's HTTP interface, path for path and status for status.
Rate limits, request checks and response headers are decided here; the data is the api space's,
reached by calling its functions."""
import gzip;
import hashlib;
import ipaddress;
import json;
import secrets;
import sys;
import urllib.parse;
import from stdjac { RemoteError }

"""A request as the server read it: header names lowercased, the first of a repeated header, the
body up to the most any route takes (`body_over` when there was more)."""
obj Request {
    has method: str,
        path: str,
        query: str,
        headers: dict[str, str],
        body: bytes,
        body_over: bool,
        peer: str;
}

"""An answer: its status, headers and body."""
obj Answer {
    has status: int,
        headers: list[tuple[str, str]] = [],
        body: bytes = b"";
}

"""The most any route reads of a body: a batch's."""
glob MAX_READ: int = 262144;

"""The largest hub post: a website report's fields at their limits, as JSON."""
glob HUB_MAX_BODY: int = 24576;

"""The largest game report."""
glob GAME_MAX_BODY: int = 131072;

"""The gate's rate limits, in memory only: per client address, and the hub's per keyed hash of
it, the key drawn at each start."""
obj Limits {
    has requests: Buckets = Buckets(),
        live: Buckets = Buckets(),
        reads: Buckets = Buckets(),
        hub: Buckets = Buckets(),
        hub_posts: Buckets = Buckets(),
        hub_key: bytes = secrets.token_bytes(16);

    """Forgets the buckets not touched for an hour."""
    def forget_idle;
}

glob cfg: Config = config_from_env(),
     limits: Limits = Limits();

"""The answer to one request."""
def answer_to(r: Request) -> Answer;

"""The address a client's requests count under: the configured header's last entry behind a
trusted proxy, else the TCP peer; an IPv6 address by its /64, an IPv4-mapped one as IPv4."""
def client(r: Request) -> str;

"""An address as the rate limits key it."""
def rate_key(ip: str) -> str;

"""The client's address hashed with the start's random key, for the hub's buckets."""
def hashed(r: Request) -> str;

"""A plain-text answer, as axum writes a `(StatusCode, String)`."""
def text(status: int, message: str) -> Answer;

"""JSON the website may read, cached `max_age` seconds."""
def json_answer(body: str, max_age: int) -> Answer;

"""A JSON answer to the website that nothing caches, with its status."""
def hub_answer(status: int, body: str) -> Answer;

"""`{"error": message}` from the hub."""
def hub_refuse(status: int, message: str) -> Answer;

"""The browser's preflight for the hub's JSON posts."""
def preflight -> Answer;

"""A query string's parameters, each its last value, decoded as forms are."""
def query_of(r: Request) -> dict[str, str];

"""A query parameter as an unsigned number of at most `most`, its default when absent;
ValueError with axum's words when it is not one."""
def query_uint(q: dict[str, str], name: str, fallback: int, most: int) -> int;

"""The same for a signed 64-bit number."""
def query_int(q: dict[str, str], name: str, fallback: int) -> int;

"""Why a query string doesn't deserialize, as axum says it."""
def query_refusal(e: ValueError) -> Answer;

"""The export's own refusal: 404 while it is off, 401 for a missing or wrong token (only these
take from the address's bucket), None to go ahead."""
def export_refusal(r: Request) -> Answer | None;

"""`same(a, b)`: the token compared whole, in a time that depends only on its length."""
def same(sent: bytes, token: bytes) -> bool;

"""Export JSON, gzipped when the client accepts it, never cached."""
def export_answer(r: Request, body: str) -> Answer;

"""A JSON body of at most `most` bytes: the value, or the hub's refusal."""
def hub_body(r: Request, most: int) -> any;

"""`POST /hub/report` and `POST /v1/report`: a report checked, then queued and opened."""
def take_report_route(r: Request, kind: str, most: int, per_day: int) -> Answer;
