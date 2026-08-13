#!/usr/bin/env python3
"""Pin the newest official OpenAI Linux package in source.nix."""

from __future__ import annotations

import base64
import re
from pathlib import Path
from urllib.request import Request, urlopen


INDEX_BASE = "https://persistent.oaistatic.com/codex-app-prod/linux/deb"
ARCHITECTURES = {
    "x86_64-linux": "amd64",
    "aarch64-linux": "arm64",
}
SOURCE_PATH = Path(__file__).with_name("source.nix")


def fetch_index(architecture: str) -> str:
    url = f"{INDEX_BASE}/dists/stable/main/binary-{architecture}/Packages"
    request = Request(url, headers={"User-Agent": "NixSlop official package updater"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8")


def package_record(index: str, architecture: str) -> dict[str, str]:
    for stanza in re.split(r"\n\s*\n", index):
        fields = dict(
            line.split(": ", 1)
            for line in stanza.splitlines()
            if ": " in line
        )
        if fields.get("Package") == "chatgpt" and fields.get("Architecture") == architecture:
            return fields
    raise RuntimeError(f"chatgpt package for architecture {architecture} was not found")


def to_sri(sha256_hex: str) -> str:
    digest = base64.b64encode(bytes.fromhex(sha256_hex)).decode("ascii")
    return f"sha256-{digest}"


def render(version: str, records: dict[str, dict[str, str]]) -> str:
    lines = ["{", f'  version = "{version}";', "", "  sources = {"]
    for index, (system, architecture) in enumerate(ARCHITECTURES.items()):
        record = records[system]
        if index:
            lines.append("")
        lines.extend(
            [
                f"    {system} = {{",
                f'      url = "{INDEX_BASE}/{record["Filename"]}";',
                f'      hash = "{to_sri(record["SHA256"])}";',
                "    };",
            ]
        )
    lines.extend(["  };", "}", ""])
    return "\n".join(lines)


def main() -> None:
    records = {
        system: package_record(fetch_index(architecture), architecture)
        for system, architecture in ARCHITECTURES.items()
    }
    versions = {record["Version"] for record in records.values()}
    if len(versions) != 1:
        raise RuntimeError(f"official package architectures have different versions: {versions}")
    SOURCE_PATH.write_text(render(versions.pop(), records), encoding="utf-8")
    print(f"updated {SOURCE_PATH} to ChatGPT Desktop {next(iter(records.values()))['Version']}")


if __name__ == "__main__":
    main()
