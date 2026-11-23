test "ids are checked for shape" {
    assert item_id("smooth-frames") and item_id("v2");
    for bad in ["", "-a", "a-", "a--b", "Smooth", "a b", "a" * 49] {
        assert not item_id(bad), bad;
    }
    assert voter_id("0b7c3c9e-3f0a-4d8e-9a39-4c1f5a6b7d21") and not voter_id("short");
}
