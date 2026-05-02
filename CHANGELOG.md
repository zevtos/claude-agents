# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.0] - 2026-05-03

### Added
- **`gost-report`: project-paths convention.** New `_paths.py` module ships `ProjectPaths` (frozen dataclass: `root`, `docs`, `figures`, `tables`, `out`, `tex`) and `paths(start=None) → ProjectPaths` helper. Project root auto-detected by walking up from the caller's `__file__` (or CWD fallback) and matching the first marker among `.git/` → `Makefile` → `pyproject.toml` → `.claude/`. "Contains marker, not is marker" rule means a script in `<project>/.claude/gost-report/build.py` walks past `.claude/` and lands at `<project>/`. Both names re-exported from `gost_report` for `from gost_report import paths`.
- **`Report` auto-resolves figure and save paths.** `Report.figure(path, caption)` resolves relative paths against `<project>/docs/figures/`; absolute paths pass through. `Report.save(path=None)` defaults to `<project>/docs/report.docx`, treats relative paths as relative to `<project>/docs/`, and creates parent directories with `mkdir parents=True exist_ok=True`. `save()` now returns `Path` (was `str`). New keyword-only constructor parameter `Report(..., project_root=None)` lets callers override auto-detection. Result: agent-generated scripts drop the 5-line `Path(__file__).parent / "figures"` boilerplate and the build script can live anywhere — recommended location `<project>/.claude/gost-report/build.py` so it doesn't pollute the artefact directory.
- **`references/templates/build.py`** — copy-paste scaffold for a fresh project (see SKILL.md "Project layout" section for the full convention).

### Changed
- **BC NOTE**: `r.figure("foo.png", ...)` with a relative path previously resolved against `os.getcwd()`. It now resolves against `<project>/docs/figures/`. Real consumer scripts always built absolute paths via `Path(__file__).parent / "figures"`, so the in-the-wild break is near zero. If you hit this, either pass an absolute path (unchanged behavior) or accept the new convention. `FileNotFoundError` raised on miss now includes both input and resolved paths.
- `Report.save()` return type widened from `str` to `Path`. `print(f"Wrote {out}")` style still works.
- SKILL.md gains a "Project layout" section showing the recommended `<project>/.claude/gost-report/build.py` location and the auto-resolve rules. API table updated to reflect the new `figure`/`save` semantics and adds the `paths()` row.

## [0.7.0] - 2026-05-02

### Added
- **Installer suppresses Claude Code commit-message attribution by default (`--target claude`).** Two layers, both idempotent and reversible:
  1. **Settings flag.** `~/.claude/settings.json` gets `includeCoAuthoredBy: false` deep-merged in (existing keys preserved). Atomic write via temp file + rename through `scripts/json-merge.py` (Python 3 stdlib only); on parse error of the existing file, the original is left untouched. PowerShell uses native `ConvertFrom-Json` / `ConvertTo-Json` and skips the Python dependency.
  2. **Global `commit-msg` hook.** `scripts/git-hooks/commit-msg` is copied into `~/.git-templates/hooks/`, and `git config --global init.templateDir` is pointed at `~/.git-templates` (only if currently unset or already ours — never overrides a user-set path). The hook strips `🤖 Generated with [Claude Code]` and `Co-Authored-By: Claude <noreply@anthropic.com>` lines plus trailing blank lines via portable BSD/GNU sed.
- **`--no-attribution-fix` (Bash) / `-NoAttributionFix` (PowerShell) opt-out flag.** Skips both layers. Always implicitly off for `--target codex`.
- `--uninstall` reverses the layer: removes our hook (only if byte-identical to ours), unsets `init.templateDir` (only if it points to our path). `settings.json/includeCoAuthoredBy` is left as-is — uninstall scope stays narrow; the installer prints a one-line reminder so users can revert manually.
- New files: `scripts/git-hooks/commit-msg`, `scripts/json-merge.py`. Existing user hooks are backed up to `commit-msg.agentpipe.bak.<epoch>` before overwrite, with a loud warning.

### Changed
- `install.sh` and `install.ps1` gain three internal helpers (`do_attribution_fix` / `do_attribution_unfix` / `do_attribution_dry`) wired into install, uninstall, dry, and diff flows. Codex target unchanged.
- `docs/installation.md` adds a "Removing Claude Attribution from Commits" section with troubleshooting (existing template dir conflict, existing hook backup) and a `git filter-repo --message-callback` recipe for cleaning already-committed trailers (with explicit force-push warning — destructive, not automated).
- README "Customization" mentions the new default and how to opt out.

### Notes
- Existing repos are not retroactively modified — `git init` only seeds hooks at repo creation. To apply the hook to an existing repo, run `git init` inside it (no-op except for hooks; safe) or copy the hook into `.git/hooks/` manually. The installer surfaces this as a one-line note on every install.
- History rewrites for already-pushed commits with the trailers are documented but explicitly not automated by the installer (force-push hazard — must be coordinated with collaborators).

## [0.6.4] - 2026-05-02

### Fixed
- **`gost-report`: consumer scripts no longer need `sys.path.insert(...)` boilerplate before `from gost_report import ...`.** Previously every agent-generated script (e.g. lab `build_report.py`) had to start with `sys.path.insert(0, "/Users/.../skills/gost-report/scripts")` to make the import resolve, baking a hardcoded absolute path into every output and burning tokens on identical preamble each regeneration. `scripts/ensure_env.py` now writes a `gost_report.pth` file into the venv's `site-packages` during bootstrap (purelib path queried from the venv's own `sysconfig`, not hardcoded — works on macOS, Linux, Windows, conda). The `.pth` is rewritten if missing on every `main()` call (self-heal for venvs predating this feature or for users who manually deleted it). As belt-and-suspenders, `ensure_env.py` also prepends `<skill_dir>/scripts/` to `PYTHONPATH` before `os.execv` / Windows `subprocess.run` of the user script. Result: agents/users write `from gost_report import Report, TitleConfig` directly. SKILL.md Dependencies section documents the mechanism in one paragraph.

## [0.6.3] - 2026-05-02

### Fixed
- **`gost-report`: city and year no longer overflow to page 2 of the title page.** The previous implementation in `_build_title_page` placed `Санкт-Петербург` and `2026` as the last two paragraphs of a stream-of-paragraphs builder, padded above by 14 fixed blank-paragraph spacers (6 + 4 + 4). Page-1 budget left only ~99pt of slack, so any single extra wrap of `university_full`, `topic`, the teacher line, or `student_name` pushed the year onto a near-empty page 2 (and the body section break shifted body content to page 3). New approach: emit city + year as a borderless single-column floating table anchored to the bottom margin via OOXML `w:tblpPr` (`vertAnchor=margin`, `tblpYSpec=bottom`, `horzAnchor=margin`, `tblpXSpec=center`). The footer is now pinned to the bottom of page 1 regardless of how the rest of the title page lays out — robust against long topics, multi-line ministry/university strings, long teacher titles, and custom `UniversityProfile` margins.

## [0.6.2] - 2026-04-27

### Fixed
- **`gost-report`: nested N-ary operators (∑∑, ∫∑, ∑∏, …) no longer leave a placeholder square between the inner operator and its body.** v0.5.0 collected the body of an N-ary operator at the `mrow` level via lookahead, but only one level deep — the inner operator's `<m:e>` stayed empty because its body siblings were consumed at the outer level instead. Refactored the lookahead into a recursive walker (`_walk_with_nary`) that, when it encounters a nested N-ary inside an outer N-ary's body, recurses to collect the inner one's body first. Result: `J = \sum_{c=1}^{k} \sum_{x \in C_c} \|x - \mu_c\|^2` now produces a properly nested `<m:nary><m:e><m:nary><m:e>‖x−μ_c‖²` structure instead of two siblings with the norm-squared dangling outside. Verified end-to-end on `\sum\sum`, `\sum\prod`, and the original 8-formula regression suite — 0 empty `<m:e>` left.

## [0.6.1] - 2026-04-27

### Changed
- **`gost-report` SKILL.md surfaces `TitleConfig` configurable fields directly.** A real-world session showed the agent assuming `teacher_label="Проверил"` was a hard-coded title-page string, when it's actually a TitleConfig field that takes any value (`"Проверила"` for a female teacher, `"Руководитель"` for theses/term papers). Two small additions to plug this blind spot:
  1. The minimal-workflow example now passes `teacher_label="Проверил"` explicitly with an inline comment showing the alternatives, so the agent sees the option as part of the canonical template.
  2. A compact `TitleConfig — часто переопределяемые поля` table after the methods table covers the five fields agents most often miss (`teacher_label`, `work_number`, `variant`, `teacher_degree`, `teacher_position`), with a pointer to `references/api.md` for the full list. ~10 extra lines in SKILL.md to prevent a recurring class of mistake.

## [0.6.0] - 2026-04-27

### Added
- **Local eval framework for agent prompts: `scripts/eval.sh` + `tests/` + `docs/eval.md`.** Runs agent under test in `claude -p` headless mode (using the user's Claude Code OAuth — no API key required), then runs an LLM-as-judge step against a written rubric. Costs ~2 subscription messages per scenario. Designed for hand-iteration on agent prompts; **not wired to CI** by design, to avoid burning quota on every PR.
- Layout: `tests/<agent>/<scenario>/input.md` (what's sent to the agent) and `rubric.md` (what the judge checks against). After a run, the same folder gets `last_output.md` and `last_verdict.json` (gitignored — local debug artifacts).
- Runner CLI: `bash scripts/eval.sh --list` discovers scenarios and prints a cost estimate without making any calls; `bash scripts/eval.sh <agent>` runs all scenarios for one agent; `bash scripts/eval.sh <agent> <scenario>` runs exactly one. Returns non-zero exit code if any scenario fails (so it's still scriptable manually).
- `tests/` ships empty on purpose — real scenarios should be sourced from open-source datasets (OWASP/CWE, real PR comments, postmortems) and thoughtfully designed per agent, not bulk-generated. `tests/README.md` documents the format; `docs/eval.md` is the full guide with a worked SQL-injection example end-to-end.

### Changed
- README structure block now lists `tests/` and `scripts/eval.sh`; the Documentation section links to `docs/eval.md`.
- CLAUDE.md commands list and structure block updated with the new eval entries.
- `.gitignore` adds `tests/*/*/last_output.md` and `tests/*/*/last_verdict.json` so local eval artifacts don't pollute git status.

## [0.5.2] - 2026-04-27

### Added
- **One-shot installer upgrade: `bash install.sh --update` (Bash) / `.\install.ps1 -Update` (PowerShell).** Runs `git pull --ff-only` against the cloned repo and then re-installs. Refuses to run if the working tree has uncommitted changes (lists them and exits) or if the remote has diverged (asks the user to resolve manually). Equivalent to the previous two-step `git pull && bash install.sh` but in one command. Help text and `docs/installation.md` updated accordingly.

## [0.5.1] - 2026-04-27

### Changed
- **`gost-report` SKILL.md compacted from ~270 to ~140 lines.** Detail-heavy sections (alternate university profiles, full LaTeX subset, typical content patterns by work type, behaviour notes, extended TitleConfig docs) moved into `references/*.md` — loaded on demand by the agent rather than always-resident. The `⛔ Правило №1` (no em-dashes) and `Writing style` blocks stay in SKILL.md verbatim because they govern every line of generated prose. Net effect: agent invocations carry ~50% less skill context, with the same enforcement on writing rules.
- New reference docs: `references/profiles.md` (UniversityProfile fields, GOST/ITMO presets, custom profile examples), `references/formulas.md` (full LaTeX subset, edge cases, sanitizer vs LaTeX, debugging), `references/patterns.md` (content structure for лаб/ВКР/курсовых/практик/ДЗ), `references/api.md` (TitleConfig fields, behaviour notes — TOC field, list restart, no quotes around topic, image clamping, sanitizer semantics).

## [0.5.0] - 2026-04-27

### Added
- **`gost-report`: native LaTeX equations.** New API method `r.formula(latex, where=None) → int` inserts a LaTeX formula as a real Word equation (OMML), not a rendered image — the formula opens editable in Word, scales cleanly, and looks native. Supports the full `latex2mathml` subset: powers/subscripts, `\frac`, `\sqrt[n]`, Greek letters, `\sum/\int/\prod` with limits, `\bar/\hat/\vec/\tilde/\dot` accents, `pmatrix/bmatrix/vmatrix`, `\text{...}`, fenced groups. Auto-numbered «(N)» pinned to the right edge per GOST 7.32, optional `where=...` block for variable explanations renders below the formula. Returns the formula's number so prose can reference it: `f1 = r.formula(...)` → `r.text(f"По формуле ({f1}) ...")`. The LaTeX string itself bypasses `_sanitize_prose` (so `\text{1—5}` doesn't get mangled); `where` text is sanitized as normal user prose.
- **`gost-report`: isolated Python environment.** New `scripts/ensure_env.py` bootstrap manages the skill's deps in a dedicated venv at `<skill_dir>/.venv/` — fixed location, single per installation, never global. Manager preference: `uv` → `conda --prefix` → stdlib `python -m venv`. Idempotent: hashes `requirements.txt` and skips work when nothing changed (millisecond no-op on warm runs). When the skill ships a new `requirements.txt`, deps auto-update on next invocation. Two modes: `python ensure_env.py` (prints venv python path) and `python ensure_env.py <script>` (bootstraps then `os.execv`s the script with venv python). Cross-platform (POSIX + Windows), stdlib only, with best-effort flock to prevent concurrent-bootstrap races.
- **`gost-report`: `scripts/requirements.txt`** — `python-docx>=1.1.0`, `latex2mathml>=3.77.0`. Single source of truth for both pip and the bootstrap.

### Changed
- **`gost-report` SKILL.md** — `## Dependencies` rewritten: agents are now told to **never** `pip install` globally, always go through `ensure_env.py`. New `### Формулы (LaTeX)` section with examples and supported subset. New `### Запуск через ensure_env.py` block under `## How to use` documenting the bootstrap workflow. Checklist gains two items (formulas render as equations, single venv per skill).
- **Installers** (`install.sh`, `install.ps1`) and **build script** (`scripts/build-skills.sh`) — strip `.venv/` and `.venv.lock` on copy/zip in both directions (install + pull). Prevents a developer's local venv from leaking into system installations or release archives, where the absolute paths in `pyvenv.cfg` would be wrong anyway.
- **`.gitignore`** — `skills/*/.venv/` and `skills/*/.venv.lock` so `git status` stays clean during local skill development.

## [0.4.4] - 2026-04-27

### Added
- **`gost-report`: hard enforcement against em-dashes.** The soft writing-style rule from v0.4.3 was still being ignored — agents kept putting `—` into report prose. Now two layers of protection:
  1. **Prompt.** `SKILL.md` opens with a top-level "⛔ Правило №1 — приоритет выше всего остального" block right after the H1, listing exactly where em/en-dashes are forbidden (`r.text`, `r.task`, headings, list items, captions, table cells) and what to write instead (comma between words, hyphen in ranges). The old writing-style section now defers to this rule.
  2. **Code.** `gost_report.py` adds `_sanitize_prose()` — every content method (`text`, `task`, `h1/h2/h3`, `numbered`, `bullet`, table cells, and the user `caption` argument in `figure`/`table`) runs input through regexes: ` — ` / ` – ` → `, ` and bare `—`/`–` → `-`. The library-generated prefixes «Рисунок N — Описание» and «Таблица N — Описание» are untouched because the dash there is mandated by GOST and inserted by the library itself.
- The sanitizer is a safety net, not a license to relax — `SKILL.md` explicitly tells the model not to rely on it and to write without em-dashes from the start.

## [0.4.3] - 2026-04-26

### Added
- **`gost-report`: hard writing-style rule for prose.** New `## Writing style — обязательно соблюдать` section in `SKILL.md` makes the model write report body text in a natural Russian voice instead of the typical AI register: no em-dashes, no «ёлочки», no канцеляризмы («в ходе выполнения работы», «является», «данный», etc.), varied sentence rhythm. Scoped to prose only — auto-generated captions (`Рисунок N — Описание`) and canonical structural headings (`Введение`, `Заключение`) are explicitly exempt because they're library-formatted per GOST.

## [0.4.2] - 2026-04-26

### Fixed
- **`gost-report`: large screenshots no longer overflow page margins.** `figure()` now clamps the image width to the printable area (A4 width minus left+right body margins from the active profile — typically ~17 cm for ITMO, ~16.5 cm for GOST). Previously, calling `figure(path, caption)` without `width_cm` used the image's native dimensions, which for typical screenshots (1300-2500 px @ 144 DPI = 23-43 cm) extended past the right margin and into the page edge in Word. Verified end-to-end on real lab screenshots (Cisco Packet Tracer captures); images now fit cleanly. Explicitly set `width_cm` is also clamped as a safety net.
- No PIL/Pillow dependency added — image natural size is read via `docx.image.image.Image.from_file`, which python-docx already ships.

## [0.4.1] - 2026-04-26

### Changed
- **Repo renamed** `claude-agents` → `agentpipe`. New URL: https://github.com/zevtos/agentpipe. GitHub redirects the old URL automatically, so existing clones / links / `gh` commands keep working; for cleanliness run `git remote set-url origin git@github.com:zevtos/agentpipe.git`.
- README repositioned: "gated pipeline orchestration for Claude Code and Codex CLI" instead of generic "config" — the orchestration angle (`/feature` runs `pm → architect → reviewer → security → tester → docs`) is what differentiates this project from the saturated "AI config sync" namespace.
- Project identity strings in installers, build scripts, and `CLAUDE.md` updated from `claude-agents` to `agentpipe`. Past CHANGELOG entries kept verbatim for historical accuracy.

## [0.4.0] - 2026-04-26

### Added
- **Codex CLI support** — installer accepts `--target codex` (Bash) / `-Target codex` (PowerShell). Skills go to `~/.agents/skills/` (open-agent-skills standard, NOT `~/.codex/skills/`). Default target is still `claude` so existing workflows are unaffected.
- All installer actions (`install`, `--dry`, `--diff`, `--pull`, `--uninstall`) respect `--target`.
- README has a new "Codex Support" section with the per-target install matrix and rationale for skipping agents/commands in Codex mode.
- `CLAUDE.md` documents the multi-target architecture and the rule to keep both installers in sync.

### Changed
- `install.sh` rewritten with proper argument-loop parsing instead of single-flag dispatch.
- `install.ps1` rewritten with `-Target` parameter, `[ValidateSet("claude","codex")]` validation, and full skills support (the latter was missing in v0.3.x — bug fix).

### Notes
- Codex agents (TOML format in `~/.codex/agents/`) and Codex's lack of custom slash commands mean those Claude assets are intentionally skipped under `--target codex`. Auto-translating agents to TOML is a planned future feature.

## [0.3.1] - 2026-04-26

### Added
- **`skills/gost-report/LICENSE`** (MIT) — every skill now ships its own license so the standalone `.zip` is legally distributable when uploaded to Claude Chat or extracted into `~/.claude/skills/`. Same MIT terms as the repo top-level.
- `CLAUDE.md` updated: skill folders must include `LICENSE`; documented in `Skill Format` and `Adding a New Skill`.
- `SKILL.md` for `gost-report` now has a `## License` section.

## [0.3.0] - 2026-04-26

### Added
- **Skills support** — installer now copies `skills/<name>/` directories to `~/.claude/skills/<name>/` alongside agents and commands
- **`gost-report` skill** — generates Russian academic reports (`.docx`) formatted to GOST 7.32 for any vuz: лабораторные, отчёты по практике, курсовые, ВКР. Ships two profiles (`ITMO_PROFILE` as default, `GOST_PROFILE` as universal baseline) and a `UniversityProfile` dataclass for arbitrary universities (МГУ, СПбГУ, МФТИ, Бауманка, etc.)
- **`scripts/build-skills.sh`** (and `.ps1`) — packages every `skills/<name>/` into `dist/<name>.zip`
- **Release workflow** (`.github/workflows/release.yml`) — on `vX.Y.Z` tag push, builds skill zips and attaches them to the GitHub release; verifies tag matches `VERSION`
- `dist/`, `__pycache__/`, `*.pyc` added to `.gitignore`

### Changed
- Project framing: from "multi-agent orchestration" to "comprehensive Claude Code configuration" (agents + commands + skills)
- `install.sh` and `install.ps1` now also handle skills and report a unified item count
- `CLAUDE.md` documents skill format, the release flow, and the `Adding a New Skill` checklist
- All examples use placeholder names («Фамилия И.О.») — never real ones

## [0.2.0] - 2026-04-13

### Added
- **refactorer agent** — 9th specialist agent for code smell detection, duplication elimination, dead code removal, and test suite refactoring (language-agnostic)
- 4 new research docs: code smells catalog, test patterns, AI-assisted refactoring, architecture debt
- `/refactor` command now runs refactorer as mandatory first step before architect
- `CLAUDE.md` with project conventions, agent/command format specs, and contributor guide — the repo now dogfoods its own pattern
- MIT LICENSE file

### Fixed
- `/sprint` no longer hardcodes `develop` as the base branch; auto-detects the repository's default branch with fallback to `main`
- Repo URLs in README replaced with actual GitHub URL

## [0.1.0] - 2026-04-04

Initial release of claude-agents — multi-agent orchestration for Claude Code.

### Added
- 8 specialist agents: architect, pm, dba, devops, reviewer, security, tester, docs
- 15 orchestration commands: /next, /kickoff, /plan, /onboard, /feature, /fix, /refactor, /sprint, /review, /test, /audit, /deploy, /release, /db, /docs
- 10 research reference documents (security, testing, DevOps, API design, databases, mobile, AI docs)
- Bash installer for macOS, Linux, WSL, Git Bash (`install.sh`)
- PowerShell installer for Windows (`install.ps1`)
- Installer modes: `--dry`, `--diff`, `--pull`, `--uninstall`, `--version`
- Complete documentation: README, commands guide, agents guide, installation guide

### Fixed
- Shell arithmetic compatibility with `set -e` in installer (`((count++))` → `$((count + 1))`)
- Architect agent made mandatory in /plan command pipeline
