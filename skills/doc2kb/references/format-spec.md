# doc2kb — Output Format Specification

This document is the source of truth for every artefact `doc2kb` produces.
Scripts read and write to these schemas; downstream agents read them in the
second session.

## File layout

```
<kb_dir>/
├── manifest.json
├── INDEX.md
├── llms.txt
├── AGENTS.md
├── _scout.json            # scout output, kept for debugging
├── _logs/
│   └── errors.json        # extraction failures, if any
└── docs/
    ├── <doc-id>-<slug>.md
    └── ...
```

Filenames: `<doc-id>` is `doc-NNN` (zero-padded, scout-assigned). `<slug>` is
ASCII-normalized `Path(source).stem` lowercased (cyrillic and CJK chars are
dropped). Maximum length 48 chars after the prefix.

## `_scout.json`

Emitted by `scout_corpus.py`. Schema:

```json
{
  "schema_version": "1.0",
  "scout_tool": "doc2kb@<VERSION>",
  "scanned_at": "ISO-8601 UTC",
  "input_root": "/abs/path/to/input",
  "kb_root": "/abs/path/to/kb",
  "corpus": {
    "total_files": int,
    "total_size_bytes": int,
    "estimated_tokens": int,
    "estimated_extraction_seconds": int,
    "scout_elapsed_seconds": float
  },
  "files": [
    {
      "id": "doc-NNN",                       // stable, used as kb-slug prefix
      "source_path": "rel/to/input_root",
      "sha256": "hex",                       // doubles as cache key
      "size_bytes": int,
      "mime": "application/pdf" | null,
      "mime_confidence": "high" | "low",     // low if magic ↔ ext disagree
      "source_type": "pdf"|"docx"|"pptx"|"xlsx"|"md"|"txt"|"html"|"epub"|"rtf"|"odt"|"image"|"unknown",
      "pdf_class": "text"|"image_only"|"mixed"|"encrypted"|"corrupt" | null,
      "pages": int | null,
      "slides": int | null,
      "has_notes": bool | null,              // pptx
      "notes_chars": int,
      "inline_images": int,
      "has_tables": bool,
      "has_equations": bool,
      "encoding": "utf-8" | "cp1251" | ... | null,
      "extraction_strategy": "pymupdf4llm"|"mammoth"|"python-pptx"|"passthrough-md"|"passthrough-txt"|"trafilatura"|"needs_password"|"needs_ocr_or_vlm"|"not_in_mvp"|"skip",
      "estimated_tokens": int | null,
      "warnings": [string],
      "action_required": "ask_user_password_or_skip"|"ask_user_ocr_strategy"|"ask_user_proceed_huge"|"ask_user_skip_corrupt"|"ask_user_skip_unsupported" | null
    }
  ],
  "skipped_at_scout": [
    { "source_path": "rel", "reason": "..." }
  ],
  "user_decisions_needed": [
    {
      "type": "encrypted"|"scanned_pdf"|"huge_file"|"corrupt"|"unsupported_format",
      "files": ["rel/path", ...],
      "options": ["skip", ...],
      "default": "skip"
    }
  ]
}
```

## `docs/<id>-<slug>.md` frontmatter

Every extracted document has a YAML frontmatter block. Required fields:

| key                 | type        | source / meaning |
|---------------------|-------------|------------------|
| `id`                | string      | scout-assigned doc-NNN |
| `source`            | string      | relative path inside input corpus |
| `source_type`       | string      | `pdf`/`docx`/`pptx`/`md`/`txt`/`html` |
| `source_sha256`     | string      | sha256 of original bytes |
| `extraction_method` | string      | `name@version` of the extractor used |
| `extraction_date`   | string      | YYYY-MM-DD UTC |
| `tokens_estimated`  | int         | tiktoken cl100k_base count of body |
| `warnings`          | list[str]   | any extraction-time issues |

Per-type optional fields:

| key                | applies to | meaning |
|--------------------|------------|---------|
| `pages`            | pdf        | total page count |
| `slides`           | pptx       | total slide count |
| `has_notes`        | pptx       | bool — speaker notes present |
| `notes_chars`      | pptx       | total chars in notes |
| `inline_images`    | docx/pptx  | count of embedded pictures |
| `has_tables`       | docx/pptx  | bool — at least one table |
| `has_equations`    | docx       | bool — OOXML `<m:oMath>` present |
| `has_charts`       | pptx       | bool — chart shapes present |
| `has_tracked_changes` | docx    | bool — `w:ins`/`w:del` present |
| `paragraphs`       | docx       | total paragraph count |
| `source_encoding`  | md/txt/html | detected source encoding |
| `headings`         | all        | first up to 10 top-level headings, for fast index |

## Markdown body

PDF bodies use `[page N]` anchors between page contents:

```markdown
[page 1]

# Title

paragraph...

[page 2]

paragraph...
```

PPTX bodies use slide headings:

```markdown
## Slide 1: Title

slide body

### Notes

speaker notes

---

## Slide 2: Next title
...
```

Image content is **never** stored as base64 inline. Inline images in DOCX are
replaced with `<img src="" alt="image N: original alt text">` which markdownify
renders as `![image N: ...]()`.

## `manifest.json`

Emitted by `build_manifest.py`. Schema:

```json
{
  "schema_version": "1.0",
  "extraction_tool": "doc2kb@<VERSION>",
  "created_at": "ISO-8601 UTC",
  "corpus_root": "/abs/path/to/input",
  "total_documents": int,
  "total_tokens_estimated": int,
  "documents": [
    {
      "id": "doc-NNN",
      "source_path": "rel/path",
      "kb_path": "docs/doc-NNN-slug.md",
      "sha256": "hex",
      "source_type": "pdf",
      "extraction_method": "pymupdf4llm@0.0.x",
      "tokens_estimated": int,
      "warnings": [string],
      // ... copies relevant per-type fields from the doc's frontmatter
    }
  ],
  "skipped": [
    { "source_path": "rel/path", "reason": "..." }
  ],
  "errors": [
    { "source_path": "rel/path", "error": "..." }
  ]
}
```

## `INDEX.md`

Human + agent readable. Generated structure:

```markdown
# Knowledge Base Index

N document(s) extracted on YYYY-MM-DD. Estimated total: ~X,XXX tokens.

## How to use
(1. INDEX.md, 2. manifest.json, 3. AGENTS.md, 4. docs/*)

## By source type
### pdf (M document(s), ~X tokens)
- [source name](docs/doc-NNN-slug.md) — Mp, ~X tok
...

## Skipped (K)
- `path` — reason

## Errors (J)
- `path` — error
```

## `llms.txt`

llmstxt.org-compatible catalog:

```
# Knowledge Base
> N documents, ~X tokens estimated, extracted YYYY-MM-DD via doc2kb@VERSION.

## PDFs
- [source name](docs/doc-NNN-slug.md): N pages, ~X tokens
...
```

## `AGENTS.md`

Static template at `skills/doc2kb/assets/agents_template.md` is copied to
`<kb_dir>/AGENTS.md` verbatim. It instructs the second-session agent on
reading order (INDEX → manifest → docs as needed), citation policy, and
warning interpretation.

## Stdout JSON from each extract_*.py

All `extract_*.py` and `scout_corpus.py` print exactly one JSON line to
stdout. Successful extraction:

```json
{"ok": true, "out": "/abs/path/output.md", "tokens_estimated": int, "warnings": [string], ...per-type extras...}
```

Failure:

```json
{"ok": false, "reason": "error message", ...}
```

`build_manifest.py`:

```json
{"ok": true, "kb_dir": "/abs/path", "documents": int, "tokens_estimated": int, "skipped": int, "errors": int}
```

Stderr is used only for human-readable progress logs.
