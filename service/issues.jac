"""A bug report as a GitHub issue: people's text made inert (no mentions, no cross-references, no
HTML, no live links), written as the template the maintainers' tools use. Pure text: nothing here
opens an issue."""
import json;

"""What opens as an issue: its title, body and labels."""
obj Issue {
    has title: str,
        body: str,
        labels: list[str];
}

glob LABELS: list[str] = ["bug", "from-website"];

"""A zero-width space: kept in the text, it breaks a mention, a reference or a link."""
glob ZWSP: str = "​";

"""A text field's rule: its name, whether it is needed, its length in characters, whether it may
hold lines."""
obj Rule {
    has name: str,
        needed: bool,
        least: int,
        most: int,
        lines: bool;
}

"""The website's form: the bug template's fields."""
glob REPORT: list[Rule] = [
    Rule("title", True, 5, 120, False),
    Rule("did", True, 3, 2000, True),
    Rule("happened", True, 3, 2000, True),
    Rule("expected", True, 3, 2000, True),
    Rule("version", False, 0, 60, False),
    Rule("system", True, 3, 200, False),
    Rule("name", False, 0, 64, False)
];

"""Text people wrote, safe in an issue."""
def neutralise(text: str) -> str;

"""`](`, `][` and `]:` broken with a zero-width space: no markdown link or image survives."""
def break_links(text: str) -> str;

"""Text as stored: no control characters but line breaks (where allowed), trimmed."""
def clean(text: str, lines: bool) -> str;

"""A field's value as text and cleaned, or ValueError when it is not text."""
def text_field(body: dict[str, any], rule: Rule) -> str | None;

"""The website's fields checked: the cleaned object, or ValueError with what is wrong."""
def website_fields(body: any) -> dict[str, any];

"""The issue for a website report's fields."""
def website_issue(fields: dict[str, any]) -> Issue;

"""Rust's `str::lines`: split at `\n`, a trailing `\r` dropped, no empty last line."""
def rust_lines(text: str) -> list[str];

"""Rust's `char::is_control`: Unicode category Cc."""
def is_control(c: str) -> bool;

"""Rust's `char::is_alphanumeric`."""
def is_alnum(c: str) -> bool;

"""The fields as stored and compared: compact JSON, keys sorted."""
def fields_json(fields: dict[str, any]) -> str;
