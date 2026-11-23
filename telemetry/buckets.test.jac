test "a full bucket map stops growing" {
    b = Buckets();
    assert b.take(3600.0, "1", 2) and b.take(3600.0, "2", 2);
    assert not b.take(3600.0, "3", 2);
    assert len(b.tokens) == 2;
    assert b.take(3600.0, "1", 2), "known keys still count";
    b.at["2"] -= 3600.0;
    assert not b.take(3600.0, "3", 2), "it looked just now: not again within the second";
    b.swept = time.monotonic() - SWEEP_EVERY;
    assert b.take(3600.0, "3", 2);
    assert len(b.tokens) == 2;
}

test "a bucket bursts a tenth of its hour, then refills" {
    b = Buckets();
    assert all(b.take(30.0, "a") for _ in range(3));
    assert not b.take(30.0, "a");
    b.at["a"] -= 120.0;
    assert b.take(30.0, "a");
}
