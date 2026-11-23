impl at(v: any, key: str) -> any {
    if isinstance(v, dict) and key in v {
        return v[key];
    }
    return None;
}

impl as_f64(v: any) -> float | None {
    if isinstance(v, bool) {
        return None;
    }
    if isinstance(v, (int, float)) {
        return float(v);
    }
    return None;
}

impl as_str(v: any) -> str | None {
    if isinstance(v, str) {
        return v;
    }
    return None;
}

impl as_u64(v: any) -> int | None {
    if isinstance(v, bool) or not isinstance(v, int) {
        return None;
    }
    n: int = v;
    return n if n >= 0 else None;
}

impl dumps(v: any) -> str {
    return json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False);
}
