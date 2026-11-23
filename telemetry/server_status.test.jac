import threading;

"""A status answer packet holding `text`."""
def answer(text: str) -> bytes {
    body = text.encode();
    packet = write_varint(0) + write_varint(len(body)) + body;
    return write_varint(len(packet)) + packet;
}

test "addresses split into host and port" {
    assert split_address("horizon.bunchy7s.dev") == ("horizon.bunchy7s.dev", 25565);
    assert split_address("example.org:25570") == ("example.org", 25570);
    assert split_address("[::1]:25566") == ("::1", 25566);
    assert split_address("[::1]") == ("::1", 25565);
    assert split_address("example.org:http") is None;
    assert split_address(" ") is None;
}

test "varints are vanilla's" {
    for (value, raw) in [
        (0, b"\x00"),
        (127, b"\x7f"),
        (128, b"\x80\x01"),
        (25565, b"\xdd\xc7\x01"),
        (-1, b"\xff\xff\xff\xff\x0f"),
    ] {
        assert write_varint(value) == raw, str(value);
        assert read_varint(raw, 0)[0] == value;
    }
}

test "bad answers are refused" {
    for bad in [b"\x00", answer("{}")[:2]] {
        refused = False;
        try {
            read_answer(bad);
        } except ValueError {
            refused = True;
        }
        assert refused;
    }
    wrong = bytearray(answer("{}"));
    wrong[1] = 1;
    refused = False;
    try {
        read_answer(bytes(wrong));
    } except ValueError {
        refused = True;
    }
    assert refused;
    assert read_answer(answer('{"players":{"online":3}}')) == '{"players":{"online":3}}';
    assert parse_players('{"players":{"online":3}}') == Players(online=3, max=0);
}

test "a server answers its player count" {
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    listener.bind(("127.0.0.1", 0));
    listener.listen(1);
    port: int = listener.getsockname()[1];
    got: list[bytes] = [];
    def serve {
        (conn, _) = listener.accept();
        want = status_request("127.0.0.1", port);
        data = b"";
        while len(data) < len(want) {
            data += conn.recv(4096);
        }
        got.append(data);
        conn.sendall(
            answer(
                '{"version":{"name":"26.3","protocol":777},"players":{"max":100,"online":12,"sample":[]}}',
            ),
        );
        conn.close();
    }
    t = threading.Thread(target=serve);
    t.start();
    p = players(f"127.0.0.1:{port}", 2.0);
    t.join();
    listener.close();
    assert p == Players(online=12, max=100);
    assert got[0] == status_request("127.0.0.1", port);
}
