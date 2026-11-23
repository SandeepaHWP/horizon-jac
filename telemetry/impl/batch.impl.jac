impl decode_batch(body: bytes) -> Batch {
    if len(body) > MAX_COMPRESSED {
        raise ValueError(f"over {MAX_COMPRESSED} bytes");
    }
    text = b"";
    try {
        text = compression.zstd.ZstdDecompressor().decompress(body, max_length=MAX_JSON + 1);
    } except compression.zstd.ZstdError as e {
        raise ValueError(str(e));
    }
    if len(text) > MAX_JSON {
        raise ValueError(f"over {MAX_JSON} bytes inflated");
    }
    value: any = None;
    try {
        value = json.loads(text.decode("utf-8"));
    } except (ValueError, UnicodeDecodeError) as e {
        raise ValueError(str(e));
    }
    b = batch_of(value);
    if b.schema == u32(0) or int(b.schema) > SCHEMA {
        raise ValueError(f"unknown schema {b.schema}");
    }
    if not is_install_id(b.install_id) {
        raise ValueError("not an install ID");
    }
    if len(b.items) == 0 or len(b.items) > MAX_ITEMS {
        raise ValueError(f"1 to {MAX_ITEMS} items");
    }
    for it in b.items {
        why = validate(it);
        if why is not None {
            raise ValueError(why);
        }
    }
    return b;
}

impl batch_json(b: Batch) -> str {
    items = ",".join(item_json(it) for it in b.items);
    return f'{{"schema":{b.schema},"install_id":{jstr(b.install_id)},"items":[{items}]}}';
}

impl encode_batch(b: Batch) -> bytes {
    return compression.zstd.compress(batch_json(b).encode());
}
