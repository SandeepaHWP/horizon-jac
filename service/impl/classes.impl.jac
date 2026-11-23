impl ram(gb: float) -> str | None {
    if math.isnan(gb) or gb <= 0.0 {
        return None;
    }
    if gb <= 5.0 {
        return "4 GB or less";
    }
    if gb <= 10.0 {
        return "8 GB";
    }
    if gb <= 20.0 {
        return "16 GB";
    }
    if gb <= 40.0 {
        return "32 GB";
    }
    return "64 GB or more";
}

impl vram(mb: float, kind: str) -> str | None {
    if gpu_kind(kind) == "integrated" {
        return "shared";
    }
    if math.isnan(mb) or mb <= 0.0 {
        return None;
    }
    for (top, name) in [
        (2560.0, "2 GB or less"),
        (4608.0, "4 GB"),
        (6656.0, "6 GB"),
        (8704.0, "8 GB"),
        (12800.0, "12 GB"),
        (16896.0, "16 GB"),
    ] {
        if mb <= top {
            return name;
        }
    }
    return "more than 16 GB";
}

impl storage(s: str) -> str | None {
    return s if s in ["nvme", "ssd", "hdd"] else None;
}

impl os_class(s: str) -> str | None {
    return s if s in ["linux", "macos", "windows"] else None;
}

impl gpu_kind(s: str) -> str | None {
    if s in ["integrated", "IntegratedGpu"] {
        return "integrated";
    }
    if s in ["discrete", "DiscreteGpu"] {
        return "discrete";
    }
    return None;
}

impl of_report(doc: any) -> list[str | None] {
    hw = at(doc, "hardware");
    gpu = at(hw, "gpu");
    kind = as_str(at(gpu, "kind")) or "";
    ram_mb = as_f64(at(hw, "ram_mb"));
    vram_mb = as_f64(at(gpu, "vram_mb"));
    return [
        ram(ram_mb / 1024.0) if ram_mb is not None else None,
        vram(vram_mb if vram_mb is not None else 0.0, kind),
        storage(as_str(at(hw, "storage")) or ""),
        os_class(as_str(at(hw, "os")) or ""),
        gpu_kind(kind),
    ];
}

impl of_system(s: System) -> list[str | None] {
    return [
        ram(float(s.ram_gb)),
        vram(float(s.vram_mb), s.gpu_kind),
        storage(s.storage),
        os_class(s.os),
        gpu_kind(s.gpu_kind),
    ];
}
