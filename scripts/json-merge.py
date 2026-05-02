#!/usr/bin/env python3
"""
agentpipe: deep-merge a JSON literal into a target file, preserving user keys.

Usage:
    python3 scripts/json-merge.py <target-path> '<json-literal>'

Behavior:
    - Reads <target-path>, or treats as {} if missing.
    - Deep-merges the literal (objects merge recursively, scalars/arrays overwrite).
    - Atomically replaces the target (temp file + rename).
    - On parse error of the existing file: bails non-zero and leaves the original untouched.

Exit codes:
    0  merged or already current (idempotent)
    1  parse error in target or argv literal
    2  bad invocation
"""
from __future__ import annotations

import json
import os
import sys
import tempfile


def deep_merge(base: dict, overlay: dict) -> dict:
    out = dict(base)
    for key, value in overlay.items():
        if (
            key in out
            and isinstance(out[key], dict)
            and isinstance(value, dict)
        ):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} <target-path> <json-literal>", file=sys.stderr)
        return 2

    target_path = argv[1]
    try:
        overlay = json.loads(argv[2])
    except json.JSONDecodeError as exc:
        print(f"json-merge: invalid JSON literal: {exc}", file=sys.stderr)
        return 1
    if not isinstance(overlay, dict):
        print("json-merge: literal must be a JSON object", file=sys.stderr)
        return 1

    base: dict = {}
    if os.path.exists(target_path):
        try:
            with open(target_path, "r", encoding="utf-8") as fh:
                content = fh.read()
            if content.strip():
                base = json.loads(content)
            if not isinstance(base, dict):
                print(
                    f"json-merge: {target_path} is not a JSON object; refusing to merge",
                    file=sys.stderr,
                )
                return 1
        except json.JSONDecodeError as exc:
            print(
                f"json-merge: {target_path} has invalid JSON: {exc}; leaving unchanged",
                file=sys.stderr,
            )
            return 1

    merged = deep_merge(base, overlay)

    if merged == base and os.path.exists(target_path):
        return 0

    target_dir = os.path.dirname(os.path.abspath(target_path)) or "."
    os.makedirs(target_dir, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=target_dir, prefix=".json-merge.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(merged, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp_path, target_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
