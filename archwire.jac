graph layers {
    """The wire format the game, the launcher and the server share."""
    layer model { telemetry.payload | telemetry.batch; }
}

graph import {
    telemetry.payload ++> telemetry.batch {
        Batch, is_install_id, validate, batch_of, item_json, jstr
    }
}
