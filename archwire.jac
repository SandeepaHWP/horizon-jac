graph layers {
    """The wire format the game, the launcher and the server share."""
    layer model { telemetry.payload | telemetry.batch | telemetry.live | telemetry.server_status | telemetry.config | telemetry.buckets | telemetry.reply; }

    """What the server works out from what it keeps: no storage, no requests."""
    layer logic { service.jsonv | service.classes | service.summary | service.issues | service.game_report | service.checks; }

    """What the server keeps, as a graph under the shared root."""
    layer keep { service.store | service.history | service.hub; }

    """What the server holds in memory, and what it asks of others."""
    layer runtime { service.livetable | service.github; }

    """What the gate asks of the server's data."""
    layer surface { service.api; }

    """The original's HTTP interface, in front of the api."""
    layer front { gate.routes | gate.front; }

    """The check that holds the port to the original, request for request."""
    layer checks { check.diff; }
}

graph import {
    """The server's logic reads the wire format."""
    edge Reads: model --> logic;

    """What is kept is shaped by the wire format and worked out by the logic."""
    edge Keeps: model | logic --> keep;

    """The live table reads pings; the filer opens the logic's issues."""
    edge Runs: model | logic --> runtime;

    """The api's surface works through everything below it."""
    edge Serves: model | logic | keep | runtime --> surface;

    """The gate reads requests with the shared logic and calls the api's surface."""
    edge Fronts: model | logic | surface --> front;

    """The check makes its requests with the wire format."""
    edge Checks: model --> checks;

    telemetry.payload ++> telemetry.batch {
        Batch, is_install_id, validate, batch_of, item_json, jstr
    }
    telemetry.payload ++> service.classes { System }
    service.jsonv ++> service.classes { at, as_f64, as_str }
    telemetry.payload ++> service.summary { tenth, round_away }
    service.jsonv ++> service.summary { at, as_f64, as_str, as_u64, dumps }
    service.classes ++> service.summary { DIMENSIONS, of_report }
    service.issues ++> service.game_report { Issue, Rule, clean, neutralise, text_field }
    telemetry.payload ++> service.store {
        Summary, System, Batch, Kind, BUCKET_EDGES_MS, display_json, jstr, slow_json, data_json,
        round_away, tenth
    }
    service.jsonv ++> service.store { dumps }
    service.classes ++> service.store { of_system, DIMENSIONS }
    service.summary ++> service.store { Upload, MIN_INSTALLS }
    telemetry.live ++> service.history { Count, PLATFORMS }
    telemetry.payload ++> service.history { tenth }
    service.jsonv ++> service.history { dumps }
    service.store ++> service.history | service.hub { hub }
    service.store ++> service.hub { counters }
    service.jsonv ++> service.hub { dumps }
    telemetry.live ++> service.livetable { Ping, Count, PLATFORMS }
    service.issues ++> service.github { Issue }
    telemetry.payload ++> service.api { batch_of, BUCKET_EDGES_MS, tenth }
    telemetry.config ++> service.api { Config, config_from_env }
    telemetry.buckets ++> service.api { Buckets }
    telemetry.reply ++> service.api { Reply }
    telemetry.live ++> service.api { Ping, count_json }
    telemetry.server_status ++> service.api { players }
    service.jsonv ++> service.api { dumps }
    service.summary ++> service.api { summary, MIN_INSTALLS }
    service.issues ++> service.api { Issue, website_issue }
    service.game_report ++> service.api { game_issue, KIND }
    service.store ++> service.api {
        count_on, insert, delete_install, aggregate, benchmark_uploads, export_benchmarks,
        export_machines, newest_day, expire
    }
    service.history ++> service.api { live_history, record_live, prune_live, sample_of, Sample }
    service.hub ++> service.api {
        vote, votes_json, queued_on, enqueue, claim, filed, release_claim, unfiled, expire_queue,
        requeue_filing, RETRY_DAYS
    }
    service.livetable ++> service.api { live_ping, live_count, live_forget }
    service.github ++> service.api { open_issue }
    telemetry.payload ++> gate.routes { Batch }
    telemetry.batch ++> gate.routes { decode_batch, batch_json, MAX_COMPRESSED }
    telemetry.config ++> gate.routes { Config, config_from_env, parse_uint }
    telemetry.buckets ++> gate.routes { Buckets }
    telemetry.reply ++> gate.routes { Reply }
    telemetry.live ++> gate.routes { Ping, ping_of, ping_check, MAX_PING_BYTES }
    telemetry.payload ++> gate.routes { is_install_id }
    service.jsonv ++> gate.routes { dumps }
    service.checks ++> gate.routes { item_id, voter_id }
    service.issues ++> gate.routes { website_fields, fields_json }
    service.game_report ++> gate.routes { game_fields }
    service.api ++> gate.routes {
        take_batch, forget_install, totals, bench_summary, export_reports, export_hardware,
        take_ping, live_now, history, take_vote, vote_counts, take_report
    }
    telemetry.config ++> gate.front { parse_uint }
    gate.routes ++> gate.front { Request, Answer, MAX_READ, answer_to, text, cfg, limits }
    telemetry.payload ++> check.diff {
        Item, Perf, Crash, Source, Kind, System, Settings, SlowFrames, Timings, Batch
    }
    telemetry.batch ++> check.diff { encode_batch }
}

graph spaces {
    """The server's data: the kept graph, the live table, the upkeep."""
    space api: native { service.api | service.store | service.history | service.hub | service.livetable | service.github; }

    """The original's HTTP interface: rate limits, checks and headers; the data is the api's."""
    space front: native { entry gate.front; gate.routes; }

    """Serves the api space to the gate."""
    app api { run api; }

    """The side-by-side check against the original."""
    space checking: native { entry check.diff; }

    """horizon-telemetry-server, as the world reaches it."""
    app gate { run front; }

    """Runs the original and the port side by side and compares them."""
    app diff { run checking; }
}
