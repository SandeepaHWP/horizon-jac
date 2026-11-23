# horizon-telemetry-server in Jac

A port of [Horizon](https://github.com/horizon-rust/horizon)'s telemetry server
(`crates/horizon-telemetry-server`, and the parts of `crates/horizon-telemetry` it uses) from Rust
to Jac, built with **neojac 0.4.0** and nothing else. It was made to find out what neojac can and
cannot do today on a real program. **[GAPS.md](GAPS.md)** lists everything it could not do.

The original takes in opt-in performance data, crash and bug reports and benchmark uploads from
the Horizon game and launcher. It keeps them in SQLite and serves anonymous totals, a live player
count and its history, roadmap votes and bug reports (filed as GitHub issues) to Horizon's website.

## Result

- **It behaves as the original does, request for request.** `check/diff.jac` starts the original
  Rust binary and this port with the same settings, sends both the same 192 requests over 21
  scenarios (each the original's own integration tests, replayed over HTTP), and compares status,
  headers and body. 0 differences, including after both are restarted on their kept data.
- **The shared wire format is byte-identical.** A Rust oracle (`reference/oracle`) links the
  original crates at commit `2e7d2c6` and prints golden vectors. The port's tests check its item
  JSON, frame-time summaries, batch refusals, report checks and issue text against them byte for
  byte.
- **The original's tests are ported.** 64 Jac tests in 16 modules: every unit and integration test
  of the original that doesn't need the original's process, with stand-in GitHub and Minecraft
  servers on threads for the ones that do.
- **It is slower, larger and two processes.** See [Cost](#cost) and [Differences](#differences).
- **neojac's mechanical tools gave nothing usable.** `neojac absorb` took Horizon's 86 manifests in.
  `neojac port` refused every crate that holds code (GAPS.md G2, G9, G10). Everything here is
  written by hand.

## How it was made

1. **`neojac absorb crates`** on a copy of the whole Horizon workspace: 86 manifests in 2.5
   minutes. It works, but an absorbed crate offers Jac only `extern "C"` functions and Horizon has
   none (G6 to G8).
2. **`neojac port --check`** on the crates: `horizon-telemetry-server` and `horizon-telemetry`
   cannot be read at all (port's build-script run of `ring` fails, G9). Dependency-free crates are
   refused construct by construct: 162 refusals in a 560-line crate (G10). The Rust mapping
   covers numbers and control flow only, with no strings, references, enums, traits or modules (G2).
3. **A hand-designed Jac program**, below.

## Design

neojac's principle is that source says *what* and plugins decide *how*. The server's data is a
graph under `root.shared`, kept by the `store` plugin, with no SQL in the program. The data is
reached through ordinary function calls between spaces (crossings), and the upkeep is `@schedule`.

The original's HTTP interface cannot be written as a served space: endpoints there are JSON POSTs
to `/__jac/call/...`, and a function cannot read the request's headers, query, body or client
address, or set its status or headers (G3). So the port is two apps:

```
             HTTP, as the original's                    crossings (HTTP + deploy key)
 clients ─────────────────────────────▶  gate  ───────────────────────────────────▶  api
                                  (http.server)                                  (served space)
                                  rate limits, request checks,                   root.shared graph,
                                  statuses and headers                           caches, live table,
                                                                                 @schedule upkeep
```

- **`gate`** (`gate/`) is a native program on `http.server`. It holds the per-address token
  buckets, reads and checks each request with the shared logic, and answers with the original's
  exact statuses and headers. It never touches the data.
- **`api`** (`service/`) is a served space. Its functions are untagged, so only the project's own
  programs, holding the deployment's key, may call them. It keeps the graph, the response caches,
  the build budget and the in-memory live table, files reports on GitHub, and runs the upkeep
  (every 10 minutes) and the live recorder (every minute) as `@schedule`d functions.
- **Unplaced modules** (`telemetry/`, and `service/` modules with no data) hold the wire format and
  the pure logic. Each space compiles them in.

The graph:

```
root.shared ──▶ Hub "installs" ──▶ Install ──┬──▶ Session ──(machine id)──▶ Machine ◀── Hub "machines"
            │                               └──▶ Report
            ├─▶ Hub "days" ──────▶ Day (totals) ──▶ Session, Report    (each row hangs off both)
            ├─▶ Hub "players.minute" / ".hour" / ".day" ──▶ Minute, Roll   (and "official.*")
            ├─▶ Hub "votes" ─────▶ VotedItem
            └─▶ Hub "queue" ─────▶ Queued (a report and its issue)
```

A session hangs off its install and its day, so deleting an install and rebuilding a day's totals
each follow edges. A machine is kept once and counts the rows that use it. Frame summaries are
packed in the original's 80-byte layout.

The graph has no index, so finding a node by a field means loading every node under its hub. The
port keeps its own key-to-node dictionaries, built from the hubs on first use (G28).

## Layout

| Path | What |
|---|---|
| `archwire.jac` | Layers, wires, the three spaces and three apps |
| `telemetry/` | The wire format: payloads (serde-identical JSON), batches (zstd), pings, the status ping client, settings, token buckets |
| `service/` | The server's logic (`classes`, `summary`, `issues`, `game_report`, `checks`), its kept graph (`store`, `history`, `hub`), the live table, the GitHub filer, and `api`, the space's surface |
| `gate/` | The HTTP front |
| `check/diff.jac` | The side-by-side check against the original, and `--measure` |
| `reference/oracle/` | Rust: golden vectors from the original crates |
| `test/` | The oracle's vectors and the website's benchmark fixtures |
| `GAPS.md` | Every gap, bug and limitation of neojac found |

## Running

```sh
neojac build                              # dist/api-linux-x86_64, dist/gate-linux-x86_64, dist/diff-linux-x86_64
tools/run-port.sh                         # the api on 127.0.0.1:8090, the gate on :8080 (PORT, API_PORT, DATA)
neojac test                               # 64 tests
ORIGINAL=<the original's binary> dist/diff-linux-x86_64              # the side-by-side check
ORIGINAL=<...> BATCHES=1000 dist/diff-linux-x86_64 --measure         # the cost table
```

The settings are the original's environment variables (`PORT`, `HOST`, `HORIZON_TELEMETRY_*`,
`TELEMETRY_EXPORT_TOKEN`), read by both programs. The gate and the api share `JAC_DEPLOY_KEY`;
the gate finds the api at `JAC_REMOTE_API`, and the api keeps its data in `JAC_API_DATA`. The
original's binary is built with `neojac cargo build --release` in its crate.

## Cost

Measured by `check/diff.jac --measure` on one machine, both servers sent the same sessions over
HTTP (G33):

| | 1,000 sessions: original | port | 10,000 sessions: original | port |
|---|---|---|---|---|
| `POST /v1/batch`, mean | 0.8 ms | 23.1 ms | 1.4 ms | 391.9 ms |
| `GET /v1/aggregate`, built | 3 ms | 53 ms | 20 ms | 1,215 ms |
| `GET /v1/aggregate`, cached | 0.4 ms | 28.7 ms | 0.3 ms | 782.3 ms |
| Bytes kept per session | 2,236 | 5,340 | 597 | 1,804 |
| Resident memory, KiB | 7,556 | 65,668 | 9,744 | 119,624 |
| Start to first answer | 59 ms | 113 ms | 53 ms | 107 ms |

The port answers correctly but is far slower, and every call slows as the kept graph grows, a cached
read included: the store compares the whole graph in memory on each call's write (G33). At the
original's own test size of 10,000 sessions, each batch takes 0.4 s. The binaries are 22 MB each
against the original's 7 MB; a build of all three apps takes 66 s and 1.9 GB of memory.

## Differences

What the port does differently from the original. Everything else the check compares is identical.

1. **Two processes**, the gate and the api, where the original is one (G3). Each request is one
   or two local HTTP calls between them.
2. **Error texts from libraries.** A batch that is not zstd at all gets the original's
   `BadMagicNumber(n)`. Other zstd failures, and malformed JSON in a batch or a ping, get 400 as in
   the original, with neojac's library's wording instead of ruzstd's and serde's.
3. **Settings above `i64::MAX`.** The original reads some settings as `u64`; the port's `int` is
   64-bit signed, so a larger value falls back to the default.
4. **The minute recorder** runs every 60 seconds from the start, not aligned to a few seconds into
   each minute. Samples still land one per minute.
5. **The hub's rate-limit key** is a keyed BLAKE2b of the address rather than Rust's `RandomState`
   hash. Both are drawn at each start and never stored.
6. **A GitHub API base URL setting** (`HORIZON_TELEMETRY_GITHUB_API`) was added so the report path
   can be tested against a stand-in, as the original's tests inject a filer.
7. **Work-arounds for neojac bugs**, each in GAPS.md: batches cross from the gate to the api as JSON
   text (G23); "none" is `""` or `b""` in kept nodes and crossing results, never `None` (G23, G24,
   G27); HTTP/1.1 is set per handler and an IPv6 socket per server (G21); the measured sessions are built once, which avoids a collector crash (G32).

Not compared against the original: the upkeep's timing, and the official server's status ping on
the real network. The api-level tests cover both against stand-ins.
