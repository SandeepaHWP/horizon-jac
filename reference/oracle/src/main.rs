//! Prints golden vectors from the original crate, one JSON object a line.
use horizon_telemetry::batch::{self, Batch};
use horizon_telemetry::payload::*;
use horizon_telemetry::{Item, Payload, Source};
use serde_json::json;

fn timings(seed: u32, n: u32) -> Summary {
    let mut t = Timings::new();
    for i in 0..n {
        let x = (i.wrapping_mul(2_654_435_761).wrapping_add(seed)) % 4000;
        t.record(x as f32 / 7.3 + 0.05);
    }
    t.summary()
}

fn line(case: &str, v: serde_json::Value) {
    println!("{}", json!({"case": case, "out": v}));
}

fn main() {
    let system = System {
        os: "linux".into(), os_version: "Fedora Linux 43".into(), arch: "x86_64".into(),
        cpu: "AMD Ryzen 9 7950X".into(), threads: 32, cores: 16, cpu_base_mhz: 4500,
        cpu_boost_mhz: 5700, ram_gb: 64, gpu: "NVIDIA GeForce RTX 4080 \"Super\" é".into(),
        gpu_vendor: "nvidia".into(), gpu_kind: "discrete".into(), vram_mb: 16384,
        driver: "570.86".into(), backend: "Vulkan".into(), storage: "nvme".into(),
        display: Some(Display { width: 2560, height: 1440, refresh_hz: 165, scale: 1.25 }),
        power: "ac".into(), form: "desktop".into(),
    };
    let mut slow = Vec::new();
    SlowFrames::record(&mut slow, 312.5, "render.upload", 201.3);
    SlowFrames::record(&mut slow, 0.1 + 250.0, "", 0.0);
    let items = vec![
        Item { day: 20741, source: Source::Game, version: "v2026.10.15".into(),
            payload: Payload::Perf(Perf { system: system.clone(), settings: Settings {
                render_distance: 12, simulation_distance: 10, max_fps: 144, vsync: true,
                fullscreen: false, graphics: "fancy".into() }, seconds: 1800,
                frames: timings(1, 30_000), ticks: Some(timings(7, 900)), peak_ram_mb: 2300,
                to_title_ms: Some(1234), to_core_ms: None, to_rest_ms: Some(9), to_world_ms: Some(4567),
                slow_frames: slow }) },
        Item { day: 1, source: Source::Launcher, version: "0.1.5".into(),
            payload: Payload::Perf(Perf::default()) },
        Item { day: 20000, source: Source::Game, version: "v1".into(),
            payload: Payload::Crash(Crash { system: System::default(), error: "boom\n\t\u{1}".into(),
                stack: "a (b:1:2)\nc".into(), thread: "main".into(),
                details: vec![("Adapter".into(), "RTX".into()), ("".into(), "\"q\"".into())] }) },
        Item { day: 3, source: Source::Game, version: "v2".into(),
            payload: Payload::Bug(Bug { system: system.clone(), text: "Water <flickers> 🌊".into(), log: Some("line\nline".into()) }) },
        Item { day: 4, source: Source::Launcher, version: "0.1.5".into(),
            payload: Payload::Benchmark(json!({"z": 1, "a": [1.5, 2.0, 1e300, -0.0, 12345678901234567u64], "m": {"y": null, "b": "é/\u{7f}"}})) },
    ];
    for (i, item) in items.iter().enumerate() {
        line("item_json", json!({"i": i, "json": String::from_utf8(serde_json::to_vec(item).unwrap()).unwrap(),
            "valid": item.validate().err()}));
    }
    for (seed, n) in [(1u32, 30_000u32), (7, 900), (3, 1), (5, 0), (9, 100_000)] {
        line("timings", json!({"seed": seed, "n": n, "summary": timings(seed, n)}));
    }
    let id = "0123456789abcdef0123456789abcdef";
    let good = batch::encode(&Batch::new(id, items.clone()));
    let mut bad_schema = Batch::new(id, items[..1].to_vec());
    bad_schema.schema = 2;
    let cases: Vec<(&str, Vec<u8>)> = vec![
        ("good", good),
        ("not_zstd", b"not zstd".to_vec()),
        ("bad_id", batch::encode(&Batch::new("someone", items[..1].to_vec()))),
        ("bad_schema", batch::encode(&bad_schema)),
        ("no_items", batch::encode(&Batch::new(id, vec![]))),
        ("bomb", ruzstd::encoding::compress_to_vec(
            format!(r#"{{"schema":1,"install_id":"{id}","items":[],"pad":"{}"}}"#, " ".repeat(batch::MAX_JSON * 4)).as_bytes(),
            ruzstd::encoding::CompressionLevel::Fastest)),
    ];
    for (name, bytes) in cases {
        let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
        let got = batch::decode(&bytes);
        line("batch", json!({"name": name, "hex": hex, "ok": got.is_ok(), "err": got.err()}));
    }
}
