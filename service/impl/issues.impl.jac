impl is_control(c: str) -> bool {
    o = ord(c);
    return o < 32 or (o >= 127 and o < 160);
}

impl is_alnum(c: str) -> bool {
    return c.isalpha() or c.isnumeric();
}

impl rust_lines(text: str) -> list[str] {
    if text == "" {
        return [];
    }
    parts = text.split("\n");
    if parts[-1] == "" {
        parts = parts[:-1];
    }
    return [p[:-1] if p.endswith("\r") else p for p in parts];
}

impl neutralise(text: str) -> str {
    closing = [
        "close",
        "closes",
        "closed",
        "fix",
        "fixes",
        "fixed",
        "resolve",
        "resolves",
        "resolved",
    ];
    chars = list(text);
    out: list[str] = [];
    i = 0;
    while i < len(chars) {
        c = chars[i];
        nxt = chars[i + 1] if i + 1 < len(chars) else "";
        word_start = i == 0 or not is_alnum(chars[i - 1]);
        if c == "<" {
            out.append("&lt;");
        } elif c == ">" {
            out.append("&gt;");
        } elif c == "`" {
            out.append("'");
        } elif c in "@#" and nxt != "" and is_alnum(nxt) {
            out.append(c + ZWSP);
        } elif c in "gG"
            and word_start
            and i + 3 < len(chars)
            and chars[i + 1] in "hH"
            and chars[i + 2] == "-"
            and chars[i + 3] in "0123456789"
        {
            out.append(c + chars[i + 1] + ZWSP);
            i += 1;
        } else {
            word = "";
            if word_start {
                j = i;
                while j < len(chars) and chars[j].isalpha() {
                    word += chars[j].lower();
                    j += 1;
                }
            }
            if word_start and word in closing {
                out.append(c + ZWSP);
            } else {
                out.append(c);
            }
        }
        i += 1;
    }
    return break_links("".join(out).replace("github.com/", "github.com" + ZWSP + "/"));
}

impl break_links(text: str) -> str {
    out: list[str] = [];
    for (i, c) in enumerate(text) {
        out.append(c);
        if c == "]" and i + 1 < len(text) and text[i + 1] in "([:" {
            out.append(ZWSP);
        }
    }
    return "".join(out);
}

impl clean(text: str, lines: bool) -> str {
    kept: list[str] = [];
    for c in text.replace("\r\n", "\n") {
        ch = " " if not lines and c == "\n" else c;
        if not is_control(ch) or (lines and ch == "\n") {
            kept.append(ch);
        }
    }
    return "".join(kept).strip();
}

impl text_field(body: dict[str, any], rule: Rule) -> str | None {
    value = "";
    if rule.name in body and body[rule.name] is not None {
        raw = body[rule.name];
        if not isinstance(raw, str) {
            raise ValueError(f"{rule.name} is text");
        }
        value = clean(raw, rule.lines);
    }
    if value == "" and not rule.needed {
        return None;
    }
    if len(value) < rule.least or len(value) > rule.most {
        raise ValueError(f"{rule.name}: {rule.least} to {rule.most} characters");
    }
    return value;
}

impl website_fields(body: any) -> dict[str, any] {
    if not isinstance(body, dict) {
        raise ValueError("send a JSON object");
    }
    o: dict[str, any] = body;
    out: dict[str, any] = {};
    for rule in REPORT {
        value = text_field(o, rule);
        if value is not None {
            out[rule.name] = value;
        }
    }
    return out;
}

impl website_issue(fields: dict[str, any]) -> Issue {
    def field(name: str) -> str {
        raw = fields.get(name);
        if isinstance(raw, str) {
            text = neutralise(raw);
            if text != "" {
                return text;
            }
        }
        return "not given";
    }
    title = neutralise(field("title").replace("\n", " ").replace("\r", " "));
    text = "\n".join([
        f"**What I did:**\n{field('did')}",
        f"**What happened:**\n{field('happened')}",
        f"**What I expected:**\n{field('expected')}",
        f"**Horizon version:** {field('version')}",
        f"**OS, CPU, GPU:** {field('system')}",
    ]);
    quoted = "\n".join(f"> {line}".rstrip() for line in rust_lines(text));
    signed = "";
    raw_name = fields.get("name");
    if isinstance(raw_name, str) {
        n = neutralise(raw_name);
        for ch in "*_~|[]" {
            n = n.replace(ch, "");
        }
        if n != "" {
            signed = f" by **{n}**";
        }
    }
    body = (f"{quoted}\n\nReported on playhorizon.dev{signed}\n\n<sub>Opened by the bug form on "
        "playhorizon.dev/hub. The reporter has this issue's link; they don't get GitHub "
        "notifications.</sub>");
    return Issue(title=title, body=body, labels=list(LABELS));
}

impl fields_json(fields: dict[str, any]) -> str {
    return json.dumps(fields, sort_keys=True, separators=(",", ":"), ensure_ascii=False);
}
