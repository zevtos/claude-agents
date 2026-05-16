#!/usr/bin/env python3
"""
extract_pdf_pymupdf4llm.py — Phase 4 extractor for native (text-layer) PDFs.

CLI:
    extract_pdf_pymupdf4llm.py <input_pdf> <output_md>
                              [--doc-id doc-NNN]
                              [--source-rel relative/path/in/corpus.pdf]

Effect:
    Writes <output_md> with YAML frontmatter + Markdown body. Page bodies are
    separated by `[page N]` anchors (research §3.4). Stdout receives a single
    JSON line summarizing the result.

Notes:
    - Uses pymupdf4llm.to_markdown(..., page_chunks=True) so we can inject
      page anchors and preserve per-page metadata.
    - Will flag a warning if total body length looks suspiciously small for
      the page count (likely image-only PDF that slipped past scout).
    - Never crashes the agent: extraction failure → emit_failure, exit 1.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Local-only import — _common lives next to this script (loaded via the
# doc2kb.pth that ensure_env.py wrote).
from _common import (  # noqa: E402
    clean_whitespace,
    count_tokens,
    emit_failure,
    emit_success,
    log,
    sanitize_heading,
    sha256_of,
    today_iso,
    tool_version_string,
    validate_source_rel,
    write_md,
)


EXTRACTOR_NAME = "pymupdf4llm"
MIN_CHARS_PER_PAGE = 30  # below this, suspect image-only or extraction failure


def _try_import():
    try:
        import pymupdf4llm  # type: ignore
        import pymupdf  # type: ignore
        return pymupdf4llm, pymupdf
    except Exception as e:
        emit_failure(f"pymupdf4llm not importable: {e}")
        sys.exit(1)


def extract(input_pdf: Path) -> tuple[str, dict, list[str]]:
    """Returns (body_markdown, frontmatter_extras, warnings)."""
    pymupdf4llm, pymupdf = _try_import()

    warnings: list[str] = []
    extras: dict = {}

    # Open with pymupdf first — gives us page count cheaply.
    try:
        doc = pymupdf.open(str(input_pdf))
    except Exception as e:
        raise RuntimeError(f"failed to open pdf: {e}") from e
    n_pages = doc.page_count
    doc.close()

    extras["pages"] = n_pages

    # Page-chunked extraction. Each chunk is a dict with 'text', 'metadata',
    # 'tables', 'images', etc. We only use 'text' here.
    try:
        chunks = pymupdf4llm.to_markdown(str(input_pdf), page_chunks=True,
                                         show_progress=False)
    except Exception as e:
        raise RuntimeError(f"to_markdown failed: {e}") from e

    pieces: list[str] = []
    for i, chunk in enumerate(chunks, start=1):
        text = (chunk.get("text") or "").strip()
        if not text:
            continue
        pieces.append(f"[page {i}]\n\n{text}")

    body = "\n\n".join(pieces).strip() + "\n"
    body = clean_whitespace(body)

    # Min-length guard (R2 in risk register).
    total_chars = len(body)
    if n_pages > 0 and total_chars < n_pages * MIN_CHARS_PER_PAGE:
        warnings.append(
            f"suspiciously small extraction: {total_chars} chars over {n_pages} pages "
            f"(possible scanned/image-only PDF that bypassed scout)"
        )

    # Try to detect a few headings for the manifest (top-level "# ..." lines).
    headings = []
    for line in body.split("\n"):
        if line.startswith("# ") and len(line) < 200:
            sanitized = sanitize_heading(line[2:])
            if sanitized:
                headings.append(sanitized)
            if len(headings) >= 10:
                break
    # Always emit `headings` (possibly empty) for schema consistency with
    # other extractors.
    extras["headings"] = headings

    return body, extras, warnings


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract native PDF → Markdown via pymupdf4llm.")
    ap.add_argument("input_pdf")
    ap.add_argument("output_md")
    ap.add_argument("--doc-id", default="doc-000")
    ap.add_argument("--source-rel", default=None)
    args = ap.parse_args()

    in_path = Path(args.input_pdf).expanduser().resolve()
    out_path = Path(args.output_md).expanduser().resolve()
    source_rel = args.source_rel or in_path.name
    try:
        source_rel = validate_source_rel(source_rel)
    except ValueError as e:
        emit_failure(f"invalid --source-rel: {e}")
        return 1

    if not in_path.is_file():
        emit_failure(f"input not found: {in_path}")
        return 1

    try:
        body, extras, warnings = extract(in_path)
    except Exception as e:
        emit_failure(f"extraction failed: {e}", extra={"input": str(in_path)})
        return 1

    fm = {
        "id": args.doc_id,
        "source": source_rel,
        "source_type": "pdf",
        "source_sha256": sha256_of(in_path),
        "extraction_method": f"{EXTRACTOR_NAME}@{tool_version_string()}",
        "extraction_date": today_iso(),
        "pages": extras.get("pages"),
        "headings": extras.get("headings", []),
        "tokens_estimated": count_tokens(body),
        "warnings": warnings,
    }
    write_md(out_path, fm, body)
    emit_success(out_path, body, warnings, extra={"pages": extras.get("pages")})
    return 0


if __name__ == "__main__":
    sys.exit(main())
