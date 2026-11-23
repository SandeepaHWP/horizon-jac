"""How many play on a Minecraft server, by the server-list status ping every client sends: a
handshake asking for the status state, a status request, and the server's JSON answer."""
import json;
import socket;

"""The official server, with the port its SRV record gives (SRV is not looked up here)."""
glob OFFICIAL_STATUS_ADDRESS: str = "play.playhorizon.dev:24454";

glob DEFAULT_PORT: int = 25565;

"""The protocol version the handshake names; a server answers the status of any version."""
glob PROTOCOL: int = 777;

"""The longest status answer read."""
glob MAX_ANSWER: int = 262144;

"""The players part of a status answer."""
obj Players {
    has online: int = 0,
        max: int = 0;
}

"""`host`, `host:port` or `[v6]:port` as host and port; None for anything else."""
def split_address(address: str) -> tuple[str, int] | None;

"""The handshake (next state: status) and the status request, each framed with its length."""
def status_request(host: str, port: int) -> bytes;

"""A VarInt as vanilla writes it: seven bits a byte, low first, an i32's two's complement."""
def write_varint(value: int) -> bytes;

"""A VarInt read from the front of `data` at `pos`: its value and the position after it."""
def read_varint(data: bytes, pos: int) -> tuple[int, int];

"""The status response packet's JSON, from all that was read."""
def read_answer(data: bytes) -> str;

"""`players.online` and `players.max` from a status answer."""
def parse_players(text: str) -> Players;

"""Asks `address` for its status within `timeout` seconds a step, and gives its player count.
ValueError or OSError says why not."""
def players(address: str, timeout: float) -> Players;
