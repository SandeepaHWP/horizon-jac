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

## G4. The writing-jac skill says `class` is not built; it is (docs, stale)

`neojac skills writing-jac`, rule 5: "`class` is not built yet: write `obj`." But
`neojac docs library/http` declares `class Hello(http.server.BaseHTTPRequestHandler)`, and a probe
with both `class H(BaseHTTPRequestHandler)` and `obj O(BaseHTTPRequestHandler)` checks and runs
(`neojac run`: `203 1 b'hi'` then `204 None b''`). The skill is stale or the page is wrong; neither
says which `class` means differently from `obj`.

## G5. Library examples fail the default lint (docs)

The `library/http` example writes `def do_GET -> None { ... }` with bodies inline. Pasted into a
file and checked with no `jac.toml`, `neojac check` reports W3037 (`'-> None' ... is unnecessary`)
and W3055 (body belongs in an impl) for each method: 8 errors. `neojac run` runs it anyway. A
page's example should pass `check` under the default rules, or say it is checked under others.

## G6. `absorb` does not keep manifests byte for byte (bug, docs contradiction)

`neojac docs toolchain/packages`: "the file neojac writes from it is the file that was taken in,
byte for byte". After `neojac absorb crates` on Horizon, 24 of the 86 `Cargo.toml` files differ
from what was taken in: every target key is re-quoted, `[target.'cfg(unix)'.dependencies]`
becoming `[target."cfg(unix)".dependencies]` and `'cfg(not(target_os = "macos"))'` becoming
`"cfg(not(target_os = \"macos\"))"`. TOML reads them the same, so cargo is unaffected, but every
such crate shows a diff in version control after absorb. Comments were kept.

## G7. `absorb` is slow and silent on a large workspace (minor)

`neojac absorb crates` on Horizon (86 manifests, 5 `Cargo.lock`s): 2 min 37 s wall, 933 MB peak
RSS, and no output at all until the final line. A first run interrupted part way had left a
partly written `jac.toml`. A progress line, or at least a note that it is resolving lock files,
would help.

## G8. An absorbed crate gives Jac nothing unless it exports `extern "C"` (major for Rust ports)

`neojac docs interop/rust-modules`: a crate's interface is its `#[no_mangle] extern "C"` functions,
`#[repr(C)]` structs, integer constants and integer enums. No Horizon crate exports any, so after
absorb nothing of `horizon-telemetry` (its `Batch`, `Item`, `decode`, the payload types) can be
imported from Jac. Absorb records the manifests and nothing more. Taking a crate's ordinary Rust
API in (its structs, enums, `Result`, `String`, `Vec`) is not offered.

## G9. `port` says a crate does not compile when only port's build-script run fails (bug)

`neojac port --check crates/horizon-telemetry-server` (and `crates/horizon-telemetry`):

```
Environment variable $CARGO_MANIFEST_LINKS is not set during execution of build script
...
thread 'main' panicked at .../ring-0.17.14/build.rs:287:43:
called `Option::unwrap()` on a `None` value
crates/horizon-telemetry-server/src/lib.rs: error[E4001]: port does not translate a crate that does not compile for linux-x86_64 yet
```

But `neojac cargo build --release` in the same directory compiles the crate, `ring` included, for
linux-x86_64 (1 min 51 s). Port runs dependencies' build scripts without some of the environment
cargo gives them (guess, from the message: `CARGO_MANIFEST_LINKS` and whatever `ring`'s
`build.rs:287` reads), then reports the crate itself as not compiling. Any crate that depends on
`ring` (so `rustls`, `ureq` with TLS) cannot be port-checked at all. The read also took 307 s and
691 MB for `horizon-telemetry`.

## G10. `port` translates none of Horizon's code (measurement)

`neojac port --check` per crate:

| Crate | Rust lines | Result |
|---|---|---|
| horizon-telemetry, horizon-telemetry-server | 1 991, 4 471 | refused: G9 |
| horizon-java-properties (no dependencies) | 560 | refused, 162 refusals: 44 calls of `std`, 32 references, 23 `std` types, 13 char literals, 10 trait impls, 4 `match`, 4 pattern `let`s, 3 `Result`, 3 non-range `for`s, closures, tuples, `str` literals, one `use`, an index, a lifetime type; 3 E4005 |
| horizon-client-lib, horizon-hot-paths-game | 11, 52 | refused |
| horizon-mod-deps, horizon-mod-points, horizon-internals | 2, 4, 5 | "would port": each holds only comments |

So `port` gives no usable Jac for any of Horizon. Everything in this repository is a hand port.
