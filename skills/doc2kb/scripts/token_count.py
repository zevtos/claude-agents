#!/usr/bin/env python3
"""
token_count.py — count tokens in an already-extracted Markdown file.

CLI:
    token_count.py <input_md>

Output (stdout, JSON):
    {"ok": true, "tokens": 7204, "chars": 28932, "method": "tiktoken|heuristic"}
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from _common import count_tokens, json_stdout, read_body, _get_tiktoken_enc  # noqa


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input_md")
    args = ap.parse_args()
    p = Path(args.input_md).expanduser().resolve()
    if not p.is_file():
        json_stdout({"ok": False, "reason": f"file not found: {p}"})
        return 1
    body = read_body(p)
    method = "tiktoken" if _get_tiktoken_enc() else "heuristic"
    json_stdout({
        "ok": True,
        "input": str(p),
        "tokens": count_tokens(body),
        "chars": len(body),
        "method": method,
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
