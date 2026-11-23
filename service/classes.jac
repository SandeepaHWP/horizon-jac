"""The hardware classes the public output breaks results down by. Coarse on purpose: a class
holds many machines, and a published cell still needs three different installs."""
import math;

"""The dimensions, in the order `of_report` and `of_system` give them."""
glob DIMENSIONS: list[str] = ["ram", "vram", "storage", "os", "gpu_kind"];

"""Installed memory in GB."""
def ram(gb: float) -> str | None;

"""A GPU's own memory in MiB; an integrated GPU shares the system's."""
def vram(mb: float, kind: str) -> str | None;

def storage(s: str) -> str | None;

def os_class(s: str) -> str | None;

"""`integrated` or `discrete`, from either wording (`IntegratedGpu`, as wgpu says it)."""
def gpu_kind(s: str) -> str | None;

"""A benchmark report's classes, from its `hardware`."""
def of_report(doc: any) -> list[str | None];

"""A telemetry item's machine's classes."""
def of_system(s: System) -> list[str | None];
