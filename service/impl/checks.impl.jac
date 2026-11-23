impl item_id(id: str) -> bool {
    return 1 <= len(id) <= 48
        and not id.startswith("-")
        and not id.endswith("-")
        and "--" not in id
        and all(c in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in id);
}

impl voter_id(id: str) -> bool {
    ok = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_";
    return 16 <= len(id) <= 64 and all(c in ok for c in id);
}
