# neojac gaps found porting horizon-telemetry-server

Compiler: neojac 0.4.0 (linux-x86_64, bdb6b2746f64), installed 2026-11-23 from the latest release.
Target: https://github.com/horizon-rust/horizon (commit 2e7d2c6), crate `crates/horizon-telemetry-server`
plus the parts of `crates/horizon-telemetry` it uses.

Each entry: what I tried, what happened, the evidence, and how the port dealt with it.
Severity: **blocker** (the original's behavior cannot be reproduced), **major** (reproduced only by
leaving an abstraction or writing much more code), **minor**, **docs** (missing, wrong or stale docs).
Any guess at a cause is marked as a guess. I never read neojac's source.

---

## G1. No Rust porting skill (docs)

`neojac skills` lists `porting-from-python` and `porting-from-the-reference-design`, and
`neojac port` accepts Rust, C, C++ and JavaScript, but there is no skill for porting Rust (or C,
C++, JavaScript). `interop/port-rust` is a mapping table only: no playbook for what to do with the
large share of a crate that port refuses.

## G2. `neojac port` for Rust refuses nearly every real crate (major)

`neojac docs interop/port-rust`, "What is refused": references other than `self`, enums and
`match`, traits, generics, closures, tuples, arrays and slices, strings, modules, `use`, every macro
that expands to these (`println!` included), and every function of another crate or of std. Any
crate with a `mod`, a `String` or a `Vec` is refused whole ("A file ports whole or not at all").
Measured on Horizon below (G4).

## G3. A served space cannot express an ordinary HTTP API (blocker for wire compatibility)

From `neojac docs apps/server` and `apps/stdjac-server`:

- Endpoints are `POST /__jac/call/<space>/<module>/<name>` with a JSON envelope. The reply is
  always the envelope `{"ok": ..., "data": ...}`, and the status is chosen by stdjac (200, 400,
  401, 403, 404, 409, 500).
- `@restspec` serves a function at a path, but the function "takes no parameters", the method is
  `GET` or `POST` only, and the reply is the envelope or a `str` with one `Content-Type`.
- A program cannot read the request's query string, headers, raw body or client address, and
  cannot set a status code or a response header. Only a `transport` plugin sees
  `transport.contract.Request`/`Response`, and the principles page says a plugin "adds nothing a
  program can say".

horizon-telemetry-server needs every one of these: `POST /v1/batch` with a zstd body and
`Content-Encoding`, `DELETE /v1/installs/{id}` (path parameter, DELETE method), `?days=`,
`?range=&series=`, `?after=&limit=`, statuses 201/202/204/400/401/404/413/415/429/503,
`Access-Control-Allow-Origin`, `Cache-Control`, `OPTIONS` preflight, `Authorization: Bearer`, and
the client address for rate limits (`@limit` counts per caller, but its window, burst and refill
are not those of the original's token bucket, and it cannot key on a proxy header).

How the port deals with it: see the design section of README.md.
