impl strings(value: any, name: str) -> list[str] {
    if value is None {
        return [];
    }
    if not isinstance(value, list) {
        raise ValueError(f"{name} is a list");
    }
    items: list[any] = value;
    out: list[str] = [];
    for item in items {
        if not isinstance(item, str) {
            raise ValueError(f"{name} holds text");
        }
        out.append(clean(item, False));
    }
    return out;
}

impl game_fields(body: any) -> dict[str, any] {
    if not isinstance(body, dict) {
        raise ValueError("send a JSON object");
    }
    o: dict[str, any] = body;
    out: dict[str, any] = {};
    raw_category = o.get("category");
    category = raw_category if isinstance(raw_category, str) else "";
    if category not in ["bug", "performance"] {
        raise ValueError("category: bug or performance");
    }
    out["category"] = category;
    bug = category == "bug";
    per_category = [
        Rule("happened", bug, 10 if bug else 0, 500, False),
        Rule("measurement", not bug, 0 if bug else 10, 6000, True),
    ];
    for rule in TEXTS + per_category {
        value = text_field(o, rule);
        if value is not None {
            out[rule.name] = value;
        }
    }
    area = o.get("area");
    if isinstance(area, str) and area != "" {
        if not bug or area not in AREAS {
            raise ValueError(f"area: one of {', '.join(AREAS)}, for a bug");
        }
        out["area"] = area;
    }
    for (name, most, longest) in [("context", 30, 200), ("likely", 10, 200)] {
        items = strings(o.get(name), name);
        if len(items) > most or any(len(i) < 1 or len(i) > longest for i in items) {
            raise ValueError(f"{name}: up to {most} entries of {longest} characters");
        }
        if items {
            out[name] = items;
        }
    }
    for (name, least, most) in [("system", 1, 60), ("settings", 0, 40)] {
        raw = o.get(name);
        rows: list[any] = [];
        if raw is not None {
            if not isinstance(raw, list) {
                raise ValueError(f"{name} is a list of [label, value]");
            }
            rows = raw;
        }
        kept: list[list[str]] = [];
        for row in rows {
            pair = strings(row, name);
            if len(pair) != 2 {
                raise ValueError(f"{name} is a list of [label, value]");
            }
            if len(pair[0]) < 1 or len(pair[0]) > 40 or len(pair[1]) > 200 {
                raise ValueError(f"{name}: labels up to 40 characters, values up to 200");
            }
            kept.append(pair);
        }
        if len(kept) < least or len(kept) > most {
            raise ValueError(f"{name}: {least} to {most} rows");
        }
        if kept {
            out[name] = kept;
        }
    }
    capture = o.get("capture");
    if isinstance(capture, str) and capture != "" {
        prefix = f"{WEBSITE}{CAPTURE_PATH}";
        id = capture[len(prefix):] if capture.startswith(prefix) else "";
        if id == "" or len(id) > 64 or not all(c.isascii() and c.isalnum() for c in id) {
            raise ValueError(f"capture: a link under {prefix}");
        }
        out["capture"] = capture;
    }
    return out;
}

impl game_issue(fields: dict[str, any]) -> Issue {
    def get(name: str) -> str {
        v = fields.get(name);
        return v if isinstance(v, str) else "";
    }
    def rows(name: str) -> list[any] {
        v = fields.get(name);
        return v if isinstance(v, list) else [];
    }
    def code(text: str) -> str {
        return "```text\n" + text.replace("`", "'") + "\n```";
    }
    def cell(text: str) -> str {
        return neutralise(text).replace("|", "/").replace("\n", " ");
    }
    def table(listed: list[any]) -> str {
        out = "| | |\n|---|---|\n";
        for row in listed {
            pair: list[any] = row;
            label = cell(pair[0] if isinstance(pair[0], str) else "");
            value = cell(pair[1] if isinstance(pair[1], str) else "");
            out += f"| {label} | {value if value != '' else 'not given by the system'} |\n";
        }
        return out;
    }
    def bullets(listed: list[any]) -> str {
        return "\n".join(f"- {neutralise(i if isinstance(i, str) else '')}" for i in listed);
    }
    bug = get("category") == "bug";
    parts: list[str] = [];
    said: list[str] = [];
    if get("happened") != "" {
        said.append(f"**What happened:** {neutralise(get('happened'))}");
    }
    if get("expected") != "" {
        said.append(f"**What I expected:** {neutralise(get('expected'))}");
    }
    if said {
        parts.append("\n>\n".join(f"> {line}" for line in said));
    }
    version = f"**Version:** {neutralise(get('version'))}";
    if get("outdated") != "" {
        version += f"\n**Older build:** {neutralise(get('outdated'))} was already out when this was sent.";
    }
    parts.append(version);
    if rows("likely") {
        parts.append(f"### Most likely\n\n{bullets(rows('likely'))}");
    }
    if get("measurement") != "" {
        measured = f"### Measurement\n\n{code(get('measurement'))}";
        if get("capture") != "" {
            measured += f"\n\n[The whole capture]({get('capture')}) (kept 30 days)";
        }
        parts.append(measured);
    }
    parts.append(f"### Machine\n\n{table(rows('system'))}");
    if rows("settings") {
        parts.append(f"### Settings\n\n{table(rows('settings'))}");
    }
    if rows("context") {
        parts.append(f"### The last seconds\n\n{bullets(rows('context'))}");
    }
    name = neutralise(get("name"));
    for ch in "*_~|[]" {
        name = name.replace(ch, "");
    }
    signed = f" by **{name}**" if name != "" else "";
    footer = (f"Reported from the game{signed}\n\n<sub>Opened by Horizon's Report Bugs screen. The player "
        "saw this text before sending it; they have this issue's link and don't get GitHub "
        "notifications.</sub>");
    head = "\n\n".join(parts);
    log = get("log");
    body = "";
    if log == "" {
        body = f"{head}\n\n{footer}";
    } else {
        room = max(MAX_ISSUE_CHARS - (len(head) + len(footer) + 200), 0);
        cut = max(len(log) - room, 0);
        body = (f"{head}\n\n<details><summary>The end of the log</summary>\n\n{code(log[cut:])}"
            f"\n\n</details>\n\n{footer}");
    }
    labels = [LABEL];
    if bug {
        labels.append("bug");
        if get("area") != "" {
            labels.append(get("area"));
        }
    } else {
        labels.append("perf");
    }
    return Issue(title=neutralise(get("title")), body=body, labels=labels);
}
