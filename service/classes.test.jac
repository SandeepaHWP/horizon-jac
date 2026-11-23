test "classes are coarse" {
    assert ram(15.6) == "16 GB" and ram(31.0) == "32 GB" and ram(64.0) == "64 GB or more";
    assert ram(0.0) is None;
    assert vram(16376.0, "discrete") == "16 GB" and vram(8192.0, "DiscreteGpu") == "8 GB";
    assert vram(0.0, "integrated") == "shared" and vram(0.0, "") is None;
    assert storage("nvme") == "nvme" and storage("tape") is None;
    assert gpu_kind("virtual") is None;
}
