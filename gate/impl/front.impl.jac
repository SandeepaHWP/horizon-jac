impl Front.request_of -> Request | None {
    headers: dict[str, str] = {};
    for (k, v) in self.headers.items() {
        name = k.lower();
        if name not in headers {
            headers[name] = v.strip(" \t");
        }
    }
    body = b"";
    over = False;
    if headers.get("transfer-encoding", "").lower() == "chunked" {
        while True {
            size_line = self.rfile.readline(65537).split(b";")[0].strip();
            size = int(size_line, 16) if size_line else 0;
            if size == 0 {
                while self.rfile.readline(65537) not in [b"\r\n", b"\n", b""] {}
                break;
            }
            if len(body) + size > MAX_READ {
                over = True;
                self.close_connection = True;
                break;
            }
            body += self.rfile.read(size);
            self.rfile.readline(3);
        }
    } elif "content-length" in headers {
        length = int(headers["content-length"]);
        if length > MAX_READ {
            over = True;
            self.close_connection = True;
        } else {
            body = self.rfile.read(length);
        }
    }
    (path, _, query) = self.path.partition("?");
    return Request(
        method=self.command,
        path=path,
        query=query,
        headers=headers,
        body=body,
        body_over=over,
        peer=self.client_address[0],
    );
}

impl Front.write(a: Answer, head_only: bool) {
    self.send_response_only(a.status);
    self.send_header("date", email.utils.formatdate(usegmt=True));
    for (k, v) in a.headers {
        self.send_header(k, v);
    }
    if a.status != 204 {
        self.send_header("content-length", str(len(a.body)));
    }
    if self.close_connection {
        self.send_header("connection", "close");
    }
    self.end_headers();
    if not head_only and a.status != 204 {
        self.wfile.write(a.body);
    }
}

impl Front.serve {
    r: Request | None = None;
    try {
        r = self.request_of();
    } except ValueError {
        self.close_connection = True;
        self.write(text(400, "bad request"), False);
        return;
    }
    self.write(answer_to(r), self.command == "HEAD");
}

impl Front.do_GET {
    self.serve();
}

impl Front.do_HEAD {
    self.serve();
}

impl Front.do_POST {
    self.serve();
}

impl Front.do_DELETE {
    self.serve();
}

impl Front.do_OPTIONS {
    self.serve();
}

impl Front.do_PUT {
    self.serve();
}

impl Front.do_PATCH {
    self.serve();
}

impl Front.setup {
    self.protocol_version = "HTTP/1.1";
    super.setup();
}

impl Front.log_message(format: str, *args: any) {}

impl make_server(address: tuple[str, int]) -> ThreadingHTTPServer {
    if ":" not in address[0] {
        return ThreadingHTTPServer(address, Front);
    }
    srv = ThreadingHTTPServer(address, Front, bind_and_activate=False);
    srv.socket.close();
    srv.socket = socket.socket(socket.AF_INET6, socket.SOCK_STREAM);
    srv.server_bind();
    srv.server_activate();
    return srv;
}

impl sweep_limits {
    while True {
        time.sleep(600.0);
        limits.forget_idle();
    }
}

with entry {
    why = cfg.client_ip_refusal();
    if why is not None {
        print(f"horizon-telemetry-server: {why}", file=sys.stderr);
        sys.exit(1);
    }
    warning = cfg.client_ip_warning();
    if warning is not None {
        print(f"horizon-telemetry-server: WARNING: {warning}", file=sys.stderr);
    }
    days = os.environ.get("HORIZON_TELEMETRY_AGGREGATE_DAYS", "");
    if days.strip() != "" and cfg.aggregate_days is None {
        print(
            "horizon-telemetry-server: HORIZON_TELEMETRY_AGGREGATE_DAYS isn't a list of days from 1 to 366: /v1/aggregate takes any value",
            file=sys.stderr,
        );
    }
    port_text = os.environ.get("PORT", "");
    port = parse_uint(port_text, 65535) if port_text != "" else None;
    host = os.environ.get("HOST", "0.0.0.0");
    listen_port = 8080;
    if port is not None {
        listen_port = port;
    }
    address = (host, listen_port);
    srv = make_server(address);
    threading.Thread(target=sweep_limits, daemon=True).start();
    print(f"horizon-telemetry-server: listening on {srv.server_port}", file=sys.stderr, flush=True);
    srv.serve_forever();
}
