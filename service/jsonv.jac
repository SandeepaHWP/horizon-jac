"""Reading untyped JSON as serde_json's `Value` accessors do: a missing key or a value of
another type is None, never an error."""
import json;

"""`v[key]` when `v` is an object holding `key`, else None (serde's `Value::get`)."""
def at(v: any, key: str) -> any;

"""A number as a float, or None for anything else, booleans included (`as_f64`)."""
def as_f64(v: any) -> float | None;

"""A string, or None (`as_str`)."""
def as_str(v: any) -> str | None;

"""A non-negative integer, or None (`as_u64`)."""
def as_u64(v: any) -> int | None;

"""A JSON value as serde_json writes a `json!` value: compact, keys sorted."""
def dumps(v: any) -> str;
