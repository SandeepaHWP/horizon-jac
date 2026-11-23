"""horizon-telemetry-server's front: serves the original's HTTP interface on `PORT` (default
8080) at `HOST` (default every address), and answers each request through the api space."""
import http.server;
import os;
import socket;
import sys;
import threading;
import time;
import email.utils;

"""Reads each request and writes its answer, over HTTP/1.1 kept alive, as the original's server
does."""
class Front(http.server.BaseHTTPRequestHandler) {
    """Speaks HTTP/1.1, kept alive: set on each handler as it starts, since a class field here does
    not reach the base class's own reads of it."""
    override def setup;

    """The request as the routes read it, or None when its body could not be read."""
    def request_of -> Request | None;

    """Answers the request whatever its method."""
    def serve;

    """Writes an answer: its status line, a date, its headers, a length, its body."""
    def write(a: Answer, head_only: bool);

    def do_GET;

    def do_HEAD;

    def do_POST;

    def do_DELETE;

    def do_OPTIONS;

    def do_PUT;

    def do_PATCH;

    override def log_message(format: str, *args: any);
}

"""A threading server on an IPv6 address."""
class Server6(http.server.ThreadingHTTPServer) {
    static has address_family: int = socket.AF_INET6;
}

"""Every ten minutes, the rate limits' idle buckets are forgotten."""
def sweep_limits;
