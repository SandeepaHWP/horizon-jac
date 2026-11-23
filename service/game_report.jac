"""A bug report sent from the game (the pause menu's Report Bugs), checked and written as a GitHub
issue. Every report gets the label `from-game`; a bug also gets `bug` and the area the player
picked, a performance report `perf`."""

"""The kind its queue entries have."""
glob KIND: str = "game";

"""The largest body accepted: the log's end at its limit and the rest, as JSON."""
glob MAX_BODY: int = 131072;

glob LABEL: str = "from-game";

"""The areas a player may pick for a bug: the repository's area labels."""
glob AREAS: list[str] = [
    "blocks",
    "mobs",
    "rendering",
    "audio",
    "ui",
    "multiplayer",
    "saves",
    "worldgen",
    "chunks",
    "commands",
];

"""A measurement's capture, on the website's performance viewer."""
glob CAPTURE_PATH: str = "/perf/c/";

"""The website: where a capture link must point."""
glob WEBSITE: str = "https://playhorizon.dev";

"""GitHub refuses an issue body over 65,536 characters: the log's end is cut to keep under this."""
glob MAX_ISSUE_CHARS: int = 60000;

glob TEXTS: list[Rule] = [
    Rule("title", True, 5, 120, False),
    Rule("expected", False, 0, 500, False),
    Rule("version", True, 3, 80, False),
    Rule("outdated", False, 0, 80, False),
    Rule("name", False, 0, 64, False),
    Rule("log", False, 0, 40000, True),
];

"""The request's fields checked: the cleaned object, or ValueError with what is wrong."""
def game_fields(body: any) -> dict[str, any];

"""The issue for a report's fields, as `game_fields` left them."""
def game_issue(fields: dict[str, any]) -> Issue;

"""A list of text, each cleaned to one line; ValueError when it is not."""
def strings(value: any, name: str) -> list[str];
