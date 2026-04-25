from __future__ import annotations

from pathlib import Path

from throttle_me_dashboard.collectors import compute_overall, script_facts


def test_compute_overall_active() -> None:
    assert compute_overall("active", "active", "inactive", "inactive") == "ACTIVE"


def test_compute_overall_partial() -> None:
    assert compute_overall("active", "inactive", "inactive", "inactive") == "PARTIAL"


def test_compute_overall_unknown() -> None:
    assert compute_overall("unknown", "unknown", "unknown", "unknown") == "UNKNOWN"


def test_script_facts_reads_ttl_and_dns(tmp_path: Path) -> None:
    script = tmp_path / "bypass"
    script.write_text(
        "sudo iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65\n"
        "echo nameserver 1.1.1.1\n"
        "sudo iptables -t nat -A OUTPUT -j DNAT --to-destination 1.1.1.1:53\n"
    )
    assert script_facts(str(script)) == ("65", "1.1.1.1")


def test_script_facts_reads_parameterized_defaults(tmp_path: Path) -> None:
    script = tmp_path / "bypass"
    script.write_text(
        'TTL_VALUE="${TTL_VALUE:-65}"\n'
        'DNS_SERVER="${DNS_SERVER:-1.1.1.1}"\n'
        'sudo iptables -t mangle -A POSTROUTING -j TTL --ttl-set "${TTL_VALUE}"\n'
        'sudo iptables -t nat -A OUTPUT -j DNAT --to-destination "${DNS_SERVER}:53"\n'
    )
    assert script_facts(str(script)) == ("65", "1.1.1.1")
