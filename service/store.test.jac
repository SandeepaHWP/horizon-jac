import json;
import from telemetry.payload { Item, Perf, Crash, Source, Settings, SlowFrames, Timings }

glob DAY: int = 20741;

"""An install's ID from a number, as the original's tests make them."""
def install(n: int) -> str {
    return f"{n:032x}";
}

"""A play session on a Fedora machine with this GPU and render distance."""
def perf(gpu: str, distance: int) -> Item {
    t = Timings();
    for i in range(30000) {
        t.record(f32(8.0) + f32(i % 50) / f32(10.0));
    }
    return Item(
        day=u32(DAY),
        source=Source.GAME,
        version="v2026.10.15",
        kind=Kind.PERF,
        perf=Perf(
            system=System(
                os="linux",
                os_version="Fedora Linux 43",
                cpu="AMD Ryzen 9 7950X",
                threads=u16(32),
                ram_gb=u16(32),
                gpu=gpu,
                driver="570.86",
                backend="Vulkan",
            ),
            settings=Settings(
                render_distance=u8(distance), simulation_distance=u8(12), graphics="fancy"
            ),
            seconds=u32(1800),
            frames=t.summary(),
            peak_ram_mb=u32(2300),
        ),
    );
}

"""Starts again on an empty graph."""
def fresh {
    for h in [root.shared --> [?:Hub]] {
        remove(h);
    }
    forget_lookups();
}

"""The totals of the 30 days to DAY."""
def totals(k: int) -> dict[str, any] {
    return json.loads(aggregate(DAY - 29, DAY, k));
}

test "totals show only groups with enough installs" {
    fresh();
    for n in range(6) {
        insert(
            Batch(
                schema=u32(1),
                install_id=install(n),
                items=[perf("NVIDIA GeForce RTX 4070", 12)] * 2,
            ),
            DAY,
        );
    }
    for n in range(10, 12) {
        insert(
            Batch(schema=u32(1), install_id=install(n), items=[perf("Intel(R) Arc A770", 8)]), DAY
        );
    }
    t = totals(5);
    groups: list[dict[str, any]] = t["groups"];
    assert len(groups) == 1, "two installs are too few to show";
    g = groups[0];
    assert g["gpu_vendor"] == "nvidia";
    assert (g["sessions"], g["install_days"]) == (12, 6);
    assert g["hours"] == 6.0;
    buckets: list[int] = g["frame_buckets"];
    assert sum(buckets) == 12 * 30000;
    edges: list[float] = t["bucket_edges_ms"];
    assert len(edges) == 13;
    text = json.dumps(t);
    assert install(0) not in text and "Ryzen" not in text;
}

test "totals break down by hardware class" {
    fresh();
    for n in range(4) {
        it = perf("NVIDIA GeForce RTX 4080", 12);
        it.perf.system.ram_gb = u16(16 if n == 3 else 31);
        it.perf.system.vram_mb = u32(16376);
        it.perf.system.gpu_kind = "discrete";
        it.perf.system.storage = "hdd" if n == 3 else "nvme";
        insert(Batch(schema=u32(1), install_id=install(n), items=[it]), DAY);
    }
    t = totals(1);
    b: dict[str, any] = t["breakdowns"];
    ram: list[dict[str, any]] = b["ram"];
    assert len(ram) == 1 and ram[0]["class"] == "32 GB" and ram[0]["installs"] == 3;
    assert ram[0]["sessions"] == 3 and ram[0]["hours"] == 1.5 and ram[0]["p50_ms"] > 8.0;
    assert b["vram"][0]["class"] == "16 GB" and b["vram"][0]["installs"] == 4;
    assert len(b["storage"]) == 1;
    assert b["os"][0]["class"] == "linux" and b["gpu_kind"][0]["class"] == "discrete";
    text = json.dumps(t);
    for raw in ["16376", "570.86", "Fedora", "hdd", install(0)] {
        assert raw not in text, raw;
    }
}

test "slow frames show what froze with enough installs" {
    fresh();
    def slow(span: str, frames: int, frame_max: float, span_max: float) -> Item {
        it = perf("NVIDIA GeForce RTX 4070", 12);
        it.perf.slow_frames = [
            SlowFrames(
                span=span,
                frames=u32(frames),
                frame_max_ms=f32(frame_max),
                span_max_ms=f32(span_max),
            ),
        ];
        return it;
    }
    for (n, frame_max) in [(0, 900.0), (1, 400.0)] {
        insert(
            Batch(
                schema=u32(1),
                install_id=install(n),
                items=[slow("renderer/r_uploads", 3, frame_max, 300.0)],
            ),
            DAY,
        );
    }
    insert(
        Batch(
            schema=u32(1), install_id=install(2), items=[slow("tick/tick_mobs", 1, 260.0, 200.0)]
        ),
        DAY,
    );
    insert(
        Batch(schema=u32(1), install_id=install(3), items=[perf("NVIDIA GeForce RTX 4070", 12)]),
        DAY,
    );
    t = totals(2);
    assert t["slow_frames"] == [
        {
            "version": "v2026.10.15",
            "span": "renderer/r_uploads",
            "frames": 6,
            "sessions": 2,
            "installs": 2,
            "frame_max_ms": 900.0,
            "span_max_ms": 300.0,
        },
    ], json.dumps(t["slow_frames"]);
}

test "an install's day counts its items" {
    fresh();
    insert(Batch(schema=u32(1), install_id=install(1), items=[perf("x", 8)] * 2), DAY);
    assert count_on(install(1), DAY) == 2 and count_on(install(1), DAY + 1) == 0;
    assert count_on(install(2), DAY) == 0;
}

test "deleting an install removes its rows and its share of the totals" {
    fresh();
    crash = Item(day=u32(DAY), source=Source.GAME, version="v1", kind=Kind.CRASH, crash=Crash());
    insert(
        Batch(schema=u32(1), install_id=install(1), items=[perf("Apple M4 Pro", 12), crash]), DAY
    );
    insert(Batch(schema=u32(1), install_id=install(2), items=[perf("Apple M4 Pro", 12)]), DAY);
    assert totals(1)["groups"][0]["sessions"] == 2;
    assert totals(1)["crashes_by_version"] == [{"version": "v1", "crashes": 1}];
    assert delete_install(install(1)) == 2;
    assert newest_day(install(1)) is None;
    assert totals(1)["groups"][0]["sessions"] == 1;
    assert totals(1)["crashes_by_version"] == [];
    assert delete_install(install(1)) == 0;
}

test "raw rows expire and the totals stay" {
    fresh();
    insert(Batch(schema=u32(1), install_id=install(1), items=[perf("Apple M4 Pro", 12)]), DAY);
    assert expire(DAY + 179 - 180) == 0, "still within retention";
    assert expire(DAY + 181 - 180) == 1;
    assert newest_day(install(1)) is None;
    all: dict[str, any] = json.loads(aggregate(DAY + 181 - 365, DAY + 181, 1));
    assert all["groups"][0]["sessions"] == 1;
    assert [m for m in [hub("machines") --> [?:Machine]]] == [], "no session points at the machine";
}

test "summaries pack in 80 bytes and back" {
    t = Timings();
    for i in range(1000) {
        t.record(f32(i % 70));
    }
    s = t.summary();
    assert len(pack(s)) == 80;
    assert unpack(pack(s)) == s;
    assert unpack(b"short") is None;
    assert gpu_vendor("Intel(R) Arc A770") == "intel" and gpu_vendor("") == "unknown";
    assert gpu_vendor("Mystery") == "other" and gpu_vendor("NVIDIA GeForce RTX 4070") == "nvidia";
}
