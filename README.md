<p align="center">
  <img src="assets/logo.svg" width="180" alt="agentpipe">
</p>

<h1 align="center">agentpipe</h1>

<p align="center">
  <strong>Gated pipeline orchestration for Claude Code and Codex CLI.</strong><br>
  9 specialist agents, 15 multi-agent workflows, multi-vendor skills — installed globally in 30 seconds.
</p>

<p align="center">
  <a href="https://github.com/zevtos/agentpipe/releases"><img src="https://img.shields.io/github/v/release/zevtos/agentpipe?label=release&style=flat-square" alt="release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/zevtos/agentpipe?style=flat-square" alt="license"></a>
  <a href="https://github.com/zevtos/agentpipe/stargazers"><img src="https://img.shields.io/github/stars/zevtos/agentpipe?style=flat-square" alt="stars"></a>
  <a href="https://github.com/zevtos/agentpipe/releases"><img src="https://img.shields.io/github/downloads/zevtos/agentpipe/total?style=flat-square" alt="downloads"></a>
  <img src="https://img.shields.io/badge/Claude%20Code-supported-7C3AED?style=flat-square" alt="Claude Code">
  <img src="https://img.shields.io/badge/Codex%20CLI-supported-10A37F?style=flat-square" alt="Codex CLI">
</p>

---

```bash
git clone https://github.com/zevtos/agentpipe.git && cd agentpipe
bash install.sh                 # Claude Code (default)
bash install.sh --target codex  # Codex CLI (skills only)
```

Then in Claude Code:

```
$ /feature "add OAuth login"

  pm        →  spec + acceptance criteria
  architect →  API design + ADR
  implement →  code
  reviewer  →  quality gate
  security  →  threat model (parallel with reviewer)
  tester    →  test suite
  docs      →  API.md update
```

Each `→` is a gated handoff: the next agent runs only if the previous one passed. Conditional steps (e.g. `dba` only fires when migrations changed). Parallel where it makes sense (`reviewer` + `security` together).

## Why agentpipe

Vanilla Claude Code already ships agents, commands, and skills — but they're **meta-utilities** (help you use Claude Code itself: explore code, configure the status line, plan a task). agentpipe adds **domain-specialist** agents and **end-user workflow** commands on top:

| | Vanilla Claude Code | + agentpipe |
|---|---|---|
| Agents | meta/utility (`general-purpose`, `Explore`, `Plan`, `claude-code-guide`, `statusline-setup`) — generic helpers | **9 domain specialists** with role-bounded tool access (architect, dba, devops, docs, pm, refactorer, reviewer, security, tester) — e.g. reviewer = Read+Grep only, can't accidentally edit |
| Slash commands | session/config (`/init`, `/clear`, `/agents`, `/mcp`, `/model`, `/config`, ...) | **15 gated multi-agent workflows** (`/feature`, `/sprint`, `/audit`, `/release`, `/refactor`, ...) with conditional steps and parallel gates |
| Skills | dev-tooling utilities (`claude-api`, `loop`, `schedule`, `update-config`, ...) — for power-users of Claude Code | **end-user domain skills** (`gost-report` for Russian academic .docx — more on the way) |
| Per-agent model selection | global / manual | **auto** — opus for high-reasoning roles (architect, security), sonnet for the rest |
| Multi-vendor distribution | Claude Code only | **same skills** in Codex CLI via `bash install.sh --target codex` |
| Skill release packaging | n/a (manual) | `bash scripts/build-skills.sh` + GH Actions auto-attaches zips on tag push |

## What's Inside

### Agents

| Agent | Domain | Model |
|-------|--------|-------|
| architect | System design, API contracts, ADRs | opus |
| pm | Requirements, specs, acceptance criteria | sonnet |
| dba | Schema design, migrations, query optimization | sonnet |
| devops | CI/CD, Docker, observability, deployment | sonnet |
| reviewer | Code review, quality gates | sonnet |
| security | Threat modeling, OWASP, vulnerability audit | opus |
| tester | Test strategy and implementation | sonnet |
| refactorer | Code smell detection, duplication, test quality | sonnet |
| docs | API docs, ADRs, runbooks, changelogs | sonnet |

### Commands

| Command | Purpose | Agents Used |
|---------|---------|-------------|
| `/next` | What should I work on? Strategic project analysis | architect |
| `/kickoff` | Bootstrap a new project from an idea | pm + architect + dba + devops |
| `/plan` | Architecture planning (design only, no code) | architect |
| `/feature` | End-to-end feature development | pm + architect + reviewer + security + tester + docs |
| `/fix` | Bug investigation and fix | reviewer + tester |
| `/sprint` | Work through GitHub issues one by one | architect + reviewer + security + tester + dba* |
| `/refactor` | Safe refactoring with verification gates | refactorer + architect* + reviewer + tester* |
| `/review` | Multi-agent code review | reviewer + security (parallel) |
| `/test` | Test strategy, implementation, mutation testing | tester |
| `/audit` | Full security audit with threat modeling | security + architect |
| `/deploy` | Deployment pre-flight checks and readiness gate | devops + reviewer + docs |
| `/release` | Version bump, changelog, tag | docs |
| `/db` | Safe database schema migrations | dba + reviewer + tester |
| `/docs` | Generate/update project documentation | docs |
| `/onboard` | Understand a new codebase | (exploration only) |

\* conditional — only fires when relevant (e.g. `dba` only when migrations changed)

### Skills

| Skill | Purpose | Triggers on |
|-------|---------|-------------|
| `gost-report` | Generate Russian academic reports (`.docx`) formatted to GOST 7.32 — лабораторные, отчёты по практике, курсовые, ВКР. Two built-in profiles (`ITMO_PROFILE`, `GOST_PROFILE`) plus `UniversityProfile` for any other vuz. | Russian-language asks for «лабораторную», «отчёт по ГОСТ», «курсовую», «ИТМО», etc. |

Each release attaches every skill as a standalone `.zip` to the GitHub release page. Two install paths depending on where you use Claude:

- **Claude Code (CLI)** — `unzip gost-report.zip -d ~/.claude/skills/` (or `bash install.sh` from a clone)
- **Claude Chat (claude.ai)** — open any chat, go to **Customize → Skills → Add → Create skill → Upload a skill**, and pick the zip. The skill becomes globally available across all your conversations.

Adding your university? Build a `UniversityProfile` and PR it back.

## Codex Support

Codex CLI shares the open-agent-skills format with Claude, so the same `gost-report` skill folder works in both. The installer's `--target codex` flag puts skills in `~/.agents/skills/` (Codex's standard path — note: not `~/.codex/skills/`).

What gets installed per target:

| | Claude Code (`--target claude`, default) | Codex CLI (`--target codex`) |
|---|---|---|
| Skills (`skills/*/`) | `~/.claude/skills/` | `~/.agents/skills/` |
| Agents (`agents/*.md`) | `~/.claude/agents/` | skipped (Codex agents use TOML, different format) |
| Slash commands (`commands/*.md`) | `~/.claude/commands/` | skipped (Codex CLI has no custom slash commands) |

If you use both clients, run the installer twice — once per target. The two install paths don't conflict.

**Why are agents and commands skipped for Codex?**

- Codex agents are single TOML files in `~/.codex/agents/` with fields like `developer_instructions`, `model`, `sandbox_mode` — not Markdown with YAML frontmatter. Auto-translating Claude's prompts to that format is a planned future feature; for now, treat the agent files as reference and write equivalent TOML by hand if needed.
- Codex CLI has no analogue to Claude's custom slash commands — Codex equivalent of «my workflow» is a skill. The user invokes it via `$skill-name`. Many of this repo's commands (`/next`, `/feature`, etc.) could become Codex skills in a future release.

## Project Structure

```
agentpipe/
  agents/                9 specialist agent definitions
  commands/              15 orchestration commands
  skills/                Domain-specific skills (folders with SKILL.md + assets)
  research/              14 reference documents
  scripts/               build-skills.sh / .ps1 — package skills into release zips
  .github/workflows/     release.yml — auto-attaches skill zips to GH releases on tag push
  docs/                  documentation (commands.md, agents.md, installation.md)
  install.sh             bash installer (macOS/Linux/WSL)
  install.ps1            PowerShell installer (Windows)
```

## How It Works

Commands are gated pipelines. For example, `/feature` runs:

```
PM (spec) → Architect (design) → Implement → Reviewer (gate) → Tester → Docs
```

Each gate must pass before proceeding. Agents have bounded tool access (reviewer can read and grep but not write). Critical agents (architect, security) run on opus; others run on sonnet. Conditional agents (marked `*` in the commands table) only fire when relevant (e.g. `dba` runs only when schema changes are detected).

## Customization

- **Project-level overrides**:
  - Claude: `.claude/agents/`, `.claude/commands/`, `.claude/skills/` in your project
  - Codex: `.agents/skills/` in your project (or `.codex/agents/` for TOML agents)
- **Edit globals**: modify the installed files directly under the target directory
- **Fork**: fork this repo, customize, install from your fork

## Building Release Archives

```bash
bash scripts/build-skills.sh             # zips every skills/<name>/ into dist/<name>.zip
bash scripts/build-skills.sh gost-report # build a single skill
```

On `git push --tags vX.Y.Z`, the `release.yml` workflow runs the same script and attaches the zips to the GitHub release. Tag must match `VERSION` exactly.

## Documentation

- [Commands Reference](docs/commands.md) — detailed usage for each command
- [Agents Reference](docs/agents.md) — agent capabilities and responsibilities
- [Installation Guide](docs/installation.md) — install, update, and customize

## Contributing

Contributions welcome — new agents, commands, skills, and improvements to existing ones. Open an issue or submit a PR.

## License

- Repo (agents, commands, installer, docs): [MIT](LICENSE)
- Each skill carries its own license file inside `skills/<name>/LICENSE`. The `gost-report` skill is also [MIT](skills/gost-report/LICENSE) — required so the bundled `.zip` ships with a license when distributed standalone via Claude Chat or Claude Code.

## Research Documents

The `research/` directory contains reference material used by agents:

| File | Topic |
|------|-------|
| 01 | Claude Code agent patterns guide |
| 02 | Blockchain wallet security audit standards |
| 03 | Incident response and postmortems |
| 04 | Production readiness checklist (SRE) |
| 05 | Advanced testing strategies |
| 06 | DevOps and observability |
| 07 | Database engineering patterns |
| 08 | API and system design patterns |
| 09 | Mobile production best practices |
| 10 | Documentation systems for AI agents |
| 11 | Code smell detection and refactoring taxonomy |
| 12 | Test refactoring and quality patterns |
| 13 | Building an AI refactoring agent |
| 14 | Architecture-level refactoring |
