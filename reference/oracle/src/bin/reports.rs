//! Golden vectors for the bug-report text: the game's check and issue, the website's issue.
use horizon_telemetry_server::{game_report, github};
use serde_json::{Map, Value, json};

fn main() {
    let long_log: String = (0..1500).map(|i| format!("line {i} `x` @who #3\n")).collect();
    let bodies = vec![
        json!({"category": "bug", "title": "Water is black", "happened": "The water turned black", "version": "v0.4.2",
               "system": [["GPU", "RX 6600"], ["OS", "Windows | 11"]], "area": "rendering", "name": "steve_*",
               "expected": "Blue @octocat fixes #12", "context": ["opened a world", "dived"], "likely": ["shader"]}),
        json!({"category": "performance", "title": "Low fps here", "measurement": "fps 20\nframe 50 ms `x`", "version": "v0.4.2",
               "system": [["CPU", ""]], "settings": [["Render", "32"]], "capture": "https://playhorizon.dev/perf/c/abc123",
               "outdated": "v0.4.3", "log": long_log}),
        json!({"category": "bug", "title": "Short", "happened": "too short", "version": "v1", "system": [["a", "b"]]}),
        json!({"category": "chat", "title": "Hello there"}),
        json!({"category": "performance", "title": "Lag spike", "measurement": "measured something", "version": "v0.4.2",
               "system": [["a", "b"]], "area": "rendering"}),
        json!({"category": "bug", "title": "Bad area", "happened": "Something happened", "version": "v0.4.2",
               "system": [["a", "b"]], "area": "kitchen"}),
        json!({"category": "bug", "title": "Bad table", "happened": "Something happened", "version": "v0.4.2",
               "system": [["a", "b", "c"]]}),
        json!({"category": "bug", "title": "No system", "happened": "Something happened", "version": "v0.4.2"}),
        json!({"category": "bug", "title": "Bad capture", "happened": "Something happened", "version": "v0.4.2",
               "system": [["a", "b"]], "capture": "https://evil.example/perf/c/x"}),
        json!({"category": "bug", "title": "Ctrl\u{7}\tchars\r\nin title", "happened": "Line one\nline two\u{0}", "version": "v0.4.2",
               "system": [["Label\nbreak", "va|lue"]], "name": "  ", "context": vec!["x"; 31]}),
        json!({"category": "bug", "title": "[t](https://evil.example) GH-3 close", "happened": "![x](https://e.example/p.png) end",
               "version": "v0.4.2", "system": [["a", "b"]], "likely": [1]}),
        json!({"category": "bug", "title": 5}),
        json!([1, 2]),
        json!({"category": "performance", "title": "Everything at once", "measurement": "m".repeat(6000), "version": "v0.4.2",
               "system": (0..60).map(|i| json!([format!("label {i}"), "v".repeat(200)])).collect::<Vec<_>>(),
               "settings": (0..40).map(|i| json!([format!("set {i}"), "s".repeat(200)])).collect::<Vec<_>>(),
               "context": (0..30).map(|i| format!("{i} {}", "c".repeat(190))).collect::<Vec<_>>(),
               "likely": (0..10).map(|i| format!("{i} {}", "l".repeat(190))).collect::<Vec<_>>(),
               "log": (0..2000).map(|i| format!("L{i:05} ")).collect::<String>().repeat(2)}),
        json!({"category": "bug", "title": "Short ver", "happened": "too short but ten", "version": "v1", "system": [["a", "b"]]}),
    ];
    for (i, body) in bodies.iter().enumerate() {
        match game_report::check(body) {
            Ok(fields) => {
                let issue = game_report::issue(&fields);
                println!("{}", json!({"case": "game", "i": i, "body": body, "fields": Value::Object(fields),
                    "title": issue.title, "issue": issue.body, "labels": issue.labels}));
            }
            Err(e) => println!("{}", json!({"case": "game", "i": i, "body": body, "err": e})),
        }
    }
    let websites = vec![
        json!({"title": "Water is black\non AMD", "did": "Opened a world\r\nthen dived", "happened": "Black water  ",
               "expected": "Blue water", "system": "Windows 11, RX 6600", "name": "steve_", "version": "0.4"}),
        json!({"title": "Hi", "did": "x @a #b <c> `d` Resolves it github.com/a/b"}),
        json!({"name": "[x](y) ~~", "did": "line\n\nafter blank\n"}),
    ];
    for (i, body) in websites.iter().enumerate() {
        let fields: Map<String, Value> = body.as_object().cloned().unwrap_or_default();
        let issue = github::issue(&fields);
        println!("{}", json!({"case": "website", "i": i, "fields": body, "title": issue.title, "issue": issue.body, "labels": issue.labels}));
    }
    for text in ["@x #y GH-1 gh-2 aGH-3 Fixes fixture <b> `c` ]( ][ ]: github.com/x", "Ünïcödé @ä #ö Closes", ""] {
        println!("{}", json!({"case": "neutralise", "in": text, "out": github::neutralise(text)}));
    }
}
