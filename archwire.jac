graph layers {
    """The wire format the game, the launcher and the server share."""
    layer model { telemetry.payload | telemetry.batch | telemetry.live | telemetry.server_status | telemetry.config; }

    """What the server works out from what it keeps: no storage, no requests."""
    layer logic { service.jsonv | service.classes | service.summary | service.issues | service.game_report; }

    """What the server keeps, as a graph under the shared root."""
    layer keep { service.store | service.history | service.hub; }
}

graph import {
    """The server's logic reads the wire format."""
    edge Reads: model --> logic;

    """What is kept is shaped by the wire format and worked out by the logic."""
    edge Keeps: model | logic --> keep;

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
}
