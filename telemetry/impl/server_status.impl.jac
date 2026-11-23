impl split_address(address: str) -> tuple[str, int] | None {
    a = address.strip();
    if a == "" {
        return None;
    }
    def port_of(text: str) -> int | None {
        t = text[1:] if text.startswith("+") else text;
        if t == "" or not all(c in "0123456789" for c in t) or int(t) > 65535 {
            return None;
        }
        return int(t);
    }
    if a.startswith("[") {
        close = a.find("]");
        if close < 0 {
            return None;
        }
        host = a[1:close];
        after = a[close + 1:];
        if after == "" {
            return (host, DEFAULT_PORT);
        }
        if not after.startswith(":") {
            return None;
        }
        p = port_of(after[1:]);
        return (host, p) if p is not None else None;
    }
    colon = a.rfind(":");
    if colon >= 0 and ":" not in a[:colon] {
        p = port_of(a[colon + 1:]);
        return (a[:colon], p) if p is not None else None;
    }
    return (a, DEFAULT_PORT);
}

impl write_varint(value: int) -> bytes {
    v = value & 0xffffffff;
    out = bytearray();
    while True {
        if v & ~0x7f == 0 {
            out.append(v);
            return bytes(out);
        }
        out.append((v & 0x7f) | 0x80);
        v >>= 7;
    }
}

impl read_varint(data: bytes, pos: int) -> tuple[int, int] {
    value = 0;
    for i in range(5) {
        if pos >= len(data) {
            raise ValueError("failed to fill whole buffer");
        }
        b = data[pos];
        pos += 1;
        value |= (b & 0x7f) << (7 * i);
        if b & 0x80 == 0 {
            value &= 0xffffffff;
            return (value - 0x100000000 if value >= 0x80000000 else value, pos);
        }
    }
    raise ValueError("a varint longer than 5 bytes");
}

impl status_request(host: str, port: int) -> bytes {
    name = host.encode();
    handshake = (
        write_varint(0)
        + write_varint(PROTOCOL)
        + write_varint(len(name))
        + name
        + port.to_bytes(2, "big")
        + write_varint(1)
    );
    return write_varint(len(handshake)) + handshake + bytes([1, 0]);
}

impl read_answer(data: bytes) -> str {
    (length, pos) = read_varint(data, 0);
    if length <= 0 or length > MAX_ANSWER {
        raise ValueError(f"a status answer of {length} bytes");
    }
    if len(data) < pos + length {
        raise ValueError("failed to fill whole buffer");
    }
    packet = data[pos:pos + length];
    (id, at) = read_varint(packet, 0);
    if id != 0 {
        raise ValueError("not a status answer");
    }
    (text_len, at) = read_varint(packet, at);
    body = packet[at:];
    if text_len < 0 or text_len != len(body) {
        raise ValueError("a status answer of the wrong length");
    }
    return body.decode("utf-8");
}

impl parse_players(text: str) -> Players {
    value: any = json.loads(text);
    if not isinstance(value, dict) or "players" not in value {
        raise ValueError("no players in the answer");
    }
    p: any = value["players"];
    def field(k: str) -> int | None {
        if isinstance(p, dict)
            and k in p
            and isinstance(p[k], int)
            and not isinstance(p[k], bool)
            and p[k] >= 0
        {
            return p[k];
        }
        return None;
    }
    online = field("online");
    if online is None {
        raise ValueError("no players.online");
    }
    top = field("max");
    return Players(online=online, max=top if top is not None else 0);
}

impl players(address: str, timeout: float) -> Players {
    target = split_address(address);
    if target is None {
        raise ValueError("not a server address");
    }
    (host, port) = target;
    with socket.create_connection((host, port), timeout=timeout) as s {
        s.sendall(status_request(host, port));
        data = b"";
        want = -1;
        while want < 0 or len(data) < want {
            chunk = s.recv(65536);
            if not chunk {
                break;
            }
            data += chunk;
            if want < 0 {
                try {
                    (length, pos) = read_varint(data, 0);
                    want = pos + length if 0 < length <= MAX_ANSWER else len(data);
                } except ValueError {
                    want = -1;
                }
            }
        }
        return parse_players(read_answer(data));
    }
}
