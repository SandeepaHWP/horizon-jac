impl ping_of(body: bytes) -> Ping {
    value: any = None;
    try {
        value = json.loads(body.decode("utf-8"));
    } except (ValueError, UnicodeDecodeError) as e {
        raise ValueError(str(e));
    }
    if not isinstance(value, dict) {
        raise ValueError("invalid type: expected struct Ping");
    }
    o: dict[str, any] = value;
    fields = ["session", "version", "platform", "lan"];
    for key in o {
        if key not in fields {
            raise ValueError(
                f"unknown field `{key}`, expected one of `session`, `version`, `platform`, `lan`"
            );
        }
    }
    for key in fields {
        if key not in o {
            raise ValueError(f"missing field `{key}`");
        }
    }
    for key in ["session", "version", "platform"] {
        if not isinstance(o[key], str) {
            raise ValueError(f"invalid type: {key}, expected a string");
        }
    }
    if not isinstance(o["lan"], bool) {
        raise ValueError("invalid type: lan, expected a boolean");
    }
    return Ping(session=o["session"], version=o["version"], platform=o["platform"], lan=o["lan"]);
}

impl ping_check(p: Ping) -> str | None {
    if not (len(p.session) == 32 and all(c in "0123456789abcdef" for c in p.session)) {
        return "session: 32 lowercase hex digits";
    }
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .+-_";
    version_ok = (
        p.version != ""
        and len(p.version.encode()) <= MAX_VERSION
        and all(c in allowed for c in p.version)
    );
    if not version_ok {
        return "version: at most 40 letters, digits, spaces and .+-_";
    }
    if p.platform not in PLATFORMS {
        return "platform: linux, macos, windows or other";
    }
    return None;
}

impl count_json(c: Count) -> str {
    compact = (",", ":");
    versions = json.dumps(c.versions, sort_keys=True, separators=compact, ensure_ascii=False);
    platforms = json.dumps(c.platforms, sort_keys=True, separators=compact, ensure_ascii=False);
    return f'{{"playing":{c.playing},"lan":{c.lan},"versions":{versions},"platforms":{platforms}}}';
}
