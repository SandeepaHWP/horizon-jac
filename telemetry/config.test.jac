test "the windows answered can be listed" {
    assert parse_days("7, 30,90 ,366") == [7, 30, 90, 366];
    assert parse_days("") is None and parse_days(" , ") is None;
    assert parse_days("7,0") is None and parse_days("7,367") is None and parse_days("7,x") is None;
}

test "numbers parse as Rust's do" {
    assert parse_uint("42", 100) == 42 and parse_uint("+42", 100) == 42;
    assert parse_uint(" 42", 100) is None and parse_uint("4_2", 100) is None and parse_uint("101", 100) is None;
    assert parse_uint("99999999999999999999999", 9223372036854775807) is None;
    assert parse_float("1e3") == 1000.0 and parse_float(".5") == 0.5 and parse_float("-2") == -2.0;
    assert parse_float(" 1") is None and parse_float("1_0") is None and parse_float("") is None;
}

test "client address settings refuse or warn when they cannot work" {
    assert Config(trust_proxy=True).client_ip_refusal() is not None;
    assert Config(trust_proxy=True, client_ip_header="cf-connecting-ip").client_ip_refusal() is None;
    assert Config(client_ip_header="cf-connecting-ip").client_ip_warning() is not None;
    assert header_name(" CF-Connecting-IP ") == "cf-connecting-ip";
    assert header_name("") is None and header_name("bad header") is None;
}
