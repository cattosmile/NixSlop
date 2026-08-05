#!/usr/bin/env python3
"""Validate that a fixed update target changed only its owned files and locks."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class TargetContract:
    """Files and root lock inputs owned by one automation target."""

    paths: frozenset[str]
    lock_inputs: frozenset[str] = frozenset()


TARGETS: dict[str, TargetContract] = {
    "codex": TargetContract(frozenset({"packages/codex/hashes.json"})),
    "codex-desktop": TargetContract(
        frozenset({"flake.lock"}),
        frozenset({"codex-desktop-linux"}),
    ),
    "kimi-code": TargetContract(frozenset({"packages/kimi-code/hashes.json"})),
    "opencode": TargetContract(
        frozenset({"flake.lock"}),
        frozenset({"opencode"}),
    ),
    "oh-my-codex": TargetContract(
        frozenset(
            {
                "packages/oh-my-codex/Cargo.lock",
                "packages/oh-my-codex/hashes.json",
            }
        )
    ),
    "cc-switch": TargetContract(frozenset({"packages/cc-switch/hashes.json"})),
    "foundations": TargetContract(
        frozenset({"flake.lock"}),
        frozenset({"home-manager", "nixpkgs", "systems"}),
    ),
}


class ValidationError(RuntimeError):
    """An update crossed its fixed ownership boundary."""


def run_git(*args: str, text: bool = True) -> str | bytes:
    """Run git without a shell so refs and paths are never executable input."""
    result = subprocess.run(
        ["git", *args],
        check=True,
        capture_output=True,
        text=text,
    )
    return result.stdout


def changed_paths() -> set[str]:
    """Return modified paths while rejecting additions, deletes, and renames."""
    raw = run_git("status", "--porcelain=v1", "-z", "--untracked-files=all", text=False)
    assert isinstance(raw, bytes)
    entries = raw.split(b"\0")
    paths: set[str] = set()
    index = 0

    while index < len(entries):
        entry = entries[index]
        index += 1
        if not entry:
            continue
        if len(entry) < 4 or entry[2:3] != b" ":
            raise ValidationError(f"Could not parse git status entry: {entry!r}")

        status = entry[:2].decode("ascii", errors="replace")
        path = entry[3:].decode("utf-8", errors="surrogateescape")
        if "R" in status or "C" in status:
            if index < len(entries):
                renamed_from = entries[index].decode(
                    "utf-8", errors="surrogateescape"
                )
                index += 1
            else:
                renamed_from = "<missing>"
            raise ValidationError(
                f"Renames and copies are forbidden: {renamed_from} -> {path} ({status})"
            )
        if "D" in status:
            raise ValidationError(f"Deletes are forbidden: {path} ({status})")
        if "A" in status or status == "??":
            raise ValidationError(f"New files are forbidden: {path} ({status})")
        if set(status) - {" ", "M"}:
            raise ValidationError(f"Unsupported git status for {path}: {status}")
        paths.add(path)

    return paths


def root_inputs(lock: dict[str, Any]) -> dict[str, str]:
    """Return the root input mapping from a v7-style flake lock."""
    try:
        root_name = lock["root"]
        inputs = lock["nodes"][root_name]["inputs"]
    except (KeyError, TypeError) as error:
        raise ValidationError("flake.lock has no valid root input mapping") from error
    if not isinstance(inputs, dict) or not all(
        isinstance(name, str) and isinstance(node, str)
        for name, node in inputs.items()
    ):
        raise ValidationError("flake.lock root inputs must map names to node names")
    return inputs


def canonical_node(
    lock: dict[str, Any],
    node_name: str,
    stack: frozenset[str] = frozenset(),
) -> Any:
    """Represent a lock subgraph without depending on generated node names."""
    if node_name in stack:
        raise ValidationError(f"flake.lock contains an input cycle at {node_name}")
    try:
        node = lock["nodes"][node_name]
    except (KeyError, TypeError) as error:
        raise ValidationError(f"flake.lock references missing node {node_name}") from error
    if not isinstance(node, dict):
        raise ValidationError(f"flake.lock node {node_name} must be an object")

    known_fields = {"inputs", "locked", "original", "flake"}
    extra_fields = set(node) - known_fields
    if extra_fields:
        extras = ", ".join(sorted(extra_fields))
        raise ValidationError(f"flake.lock node {node_name} has unknown fields: {extras}")

    inputs = node.get("inputs", {})
    if not isinstance(inputs, dict):
        raise ValidationError(f"flake.lock node {node_name} has invalid inputs")

    next_stack = stack | {node_name}
    canonical_inputs: dict[str, Any] = {}
    for input_name, reference in sorted(inputs.items()):
        if isinstance(reference, str):
            referenced_name = reference
            follows: list[str] | None = None
        elif (
            isinstance(reference, list)
            and reference
            and all(isinstance(part, str) for part in reference)
        ):
            # A follows edge is semantic configuration, not a node reference.
            referenced_name = ""
            follows = reference
        else:
            raise ValidationError(
                f"flake.lock node {node_name} has invalid input {input_name}"
            )

        canonical_inputs[input_name] = (
            {"follows": follows}
            if follows is not None
            else canonical_node(lock, referenced_name, next_stack)
        )

    return {
        "locked": node.get("locked"),
        "original": node.get("original"),
        "flake": node.get("flake", True),
        "inputs": canonical_inputs,
    }


def reachable_nodes(lock: dict[str, Any]) -> set[str]:
    """Collect direct node references reachable from the lock root."""
    try:
        root_name = lock["root"]
        nodes = lock["nodes"]
    except (KeyError, TypeError) as error:
        raise ValidationError("flake.lock is missing root or nodes") from error

    reachable: set[str] = set()
    pending = [root_name]
    while pending:
        node_name = pending.pop()
        if node_name in reachable:
            continue
        if node_name not in nodes or not isinstance(nodes[node_name], dict):
            raise ValidationError(f"flake.lock references missing node {node_name}")
        reachable.add(node_name)
        for reference in nodes[node_name].get("inputs", {}).values():
            if isinstance(reference, str):
                pending.append(reference)
    return reachable


def validate_lock_change(
    before: dict[str, Any],
    after: dict[str, Any],
    allowed_inputs: frozenset[str],
) -> None:
    """Reject semantic changes outside the selected root input closures."""
    for key in ("root", "version"):
        if before.get(key) != after.get(key):
            raise ValidationError(f"flake.lock {key!r} changed")

    before_inputs = root_inputs(before)
    after_inputs = root_inputs(after)
    if set(before_inputs) != set(after_inputs):
        raise ValidationError("flake.lock root input names changed")

    missing = allowed_inputs - set(before_inputs)
    if missing:
        names = ", ".join(sorted(missing))
        raise ValidationError(f"flake.lock is missing target input(s): {names}")

    before_nodes = set(before.get("nodes", {}))
    after_nodes = set(after.get("nodes", {}))
    if reachable_nodes(before) != before_nodes:
        raise ValidationError("base flake.lock contains unreachable nodes")
    if reachable_nodes(after) != after_nodes:
        raise ValidationError("updated flake.lock contains unreachable nodes")

    changed_allowed_input = False
    for input_name in sorted(before_inputs):
        before_graph = canonical_node(before, before_inputs[input_name])
        after_graph = canonical_node(after, after_inputs[input_name])
        if input_name in allowed_inputs:
            changed_allowed_input |= before_graph != after_graph
        elif before_graph != after_graph:
            raise ValidationError(
                f"flake.lock changed protected root input {input_name!r}"
            )

    if not changed_allowed_input:
        names = ", ".join(sorted(allowed_inputs))
        raise ValidationError(
            f"flake.lock changed without updating the intended input(s): {names}"
        )


def load_base_lock(base_ref: str) -> dict[str, Any]:
    """Load flake.lock from the trusted base revision."""
    try:
        raw = run_git("show", f"{base_ref}:flake.lock")
    except subprocess.CalledProcessError as error:
        raise ValidationError(
            f"Could not read flake.lock from base ref {base_ref!r}"
        ) from error
    assert isinstance(raw, str)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValidationError(f"Base {base_ref}:flake.lock is invalid JSON") from error


def validate(program: str, base_ref: str, repository: Path) -> set[str]:
    """Validate one target against the current git worktree."""
    contract = TARGETS[program]
    paths = changed_paths()
    unexpected = paths - contract.paths
    if unexpected:
        names = ", ".join(sorted(unexpected))
        raise ValidationError(f"Unexpected path(s) for {program}: {names}")

    if "flake.lock" in paths:
        try:
            after = json.loads((repository / "flake.lock").read_text())
        except (OSError, json.JSONDecodeError) as error:
            raise ValidationError("Updated flake.lock is not valid JSON") from error
        validate_lock_change(load_base_lock(base_ref), after, contract.lock_inputs)

    return paths


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("program", choices=tuple(TARGETS))
    parser.add_argument(
        "--base-ref",
        default="origin/main",
        help="trusted git revision used to validate flake.lock (default: origin/main)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        paths = validate(args.program, args.base_ref, Path.cwd())
    except (ValidationError, subprocess.CalledProcessError) as error:
        print(f"update validation failed: {error}", file=sys.stderr)
        return 1

    if paths:
        print(f"validated {args.program}: {', '.join(sorted(paths))}")
    else:
        print(f"validated {args.program}: no changes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
