graph layers {
    """The wire format the game, the launcher and the server share."""
    layer model { telemetry.payload | telemetry.batch | telemetry.live | telemetry.server_status | telemetry.config; }

    """What the server works out from what it keeps: no storage, no requests."""
    layer logic { service.jsonv | service.classes | service.summary | service.issues | service.game_report; }
}

graph import {
    """The server's logic reads the wire format."""
    edge Reads: model --> logic;

    telemetry.payload ++> telemetry.batch {
        Batch, is_install_id, validate, batch_of, item_json, jstr
    }
    telemetry.payload ++> service.classes { System }
    service.jsonv ++> service.classes { at, as_f64, as_str }
    telemetry.payload ++> service.summary { tenth, round_away }
    service.jsonv ++> service.summary { at, as_f64, as_str, as_u64, dumps }
    service.classes ++> service.summary { DIMENSIONS, of_report }
    service.issues ++> service.game_report { Issue, Rule, clean, neutralise, text_field }
}
