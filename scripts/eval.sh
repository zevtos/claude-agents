#!/usr/bin/env bash
# eval.sh — local-only prompt-quality runner for agentpipe agents.
#
# Uses `claude -p` (Claude Code CLI in headless mode), so authenticates
# with the user's existing OAuth subscription — no API key required.
# Each scenario costs ~2 subscription messages (agent run + judge run).
#
# Designed for local iteration over agent prompts. Not wired to CI by
# design, to avoid burning quota on every PR.
#
# Layout: tests/<agent>/<scenario>/input.md + rubric.md
# After a run, each scenario folder also gets last_output.md and
# last_verdict.json (gitignored).
#
# Usage:
#     bash scripts/eval.sh                       # run every scenario across all agents
#     bash scripts/eval.sh <agent>               # run all scenarios for one agent
#     bash scripts/eval.sh <agent> <scenario>    # run one scenario
#     bash scripts/eval.sh --list                # list discovered scenarios + cost estimate
#     bash scripts/eval.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$REPO/agents"
TESTS_DIR="$REPO/tests"

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; CYAN=''; DIM=''; NC=''
fi

err()  { echo -e "${RED}✗${NC} $*" >&2; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*" >&2; }
info() { echo -e "${CYAN}→${NC} $*"; }

preflight() {
    if ! command -v claude >/dev/null 2>&1; then
        err "'claude' CLI not found. Install Claude Code first: https://docs.claude.com/claude-code"
        exit 2
    fi
    if [[ ! -d "$TESTS_DIR" ]]; then
        err "tests/ directory not found at $TESTS_DIR"
        exit 2
    fi
}

# --- Discovery ---

list_agents_with_scenarios() {
    for agent_file in "$AGENTS_DIR"/*.md; do
        [[ -f "$agent_file" ]] || continue
        local agent
        agent=$(basename "$agent_file" .md)
        if [[ -d "$TESTS_DIR/$agent" ]]; then
            local has_any=""
            for s in "$TESTS_DIR/$agent"/*/; do
                [[ -d "$s" && -f "$s/input.md" && -f "$s/rubric.md" ]] || continue
                has_any="yes"
                break
            done
            [[ -n "$has_any" ]] && echo "$agent"
        fi
    done
}

list_scenarios() {
    local agent="$1"
    local agent_tests="$TESTS_DIR/$agent"
    [[ -d "$agent_tests" ]] || return
    for s in "$agent_tests"/*/; do
        [[ -d "$s" && -f "$s/input.md" && -f "$s/rubric.md" ]] || continue
        basename "$s"
    done
}

count_total_scenarios() {
    local total=0
    for agent in $(list_agents_with_scenarios); do
        for _ in $(list_scenarios "$agent"); do
            total=$((total + 1))
        done
    done
    echo "$total"
}

# --- Run a single scenario ---

run_scenario() {
    local agent="$1"
    local scenario="$2"
    local agent_file="$AGENTS_DIR/${agent}.md"
    local scenario_dir="$TESTS_DIR/$agent/$scenario"
    local input_file="$scenario_dir/input.md"
    local rubric_file="$scenario_dir/rubric.md"

    if [[ ! -f "$agent_file" ]]; then
        err "$agent: no agents/${agent}.md"
        return 1
    fi
    if [[ ! -f "$input_file" || ! -f "$rubric_file" ]]; then
        err "$agent/$scenario: missing input.md or rubric.md"
        return 1
    fi

    local agent_prompt
    agent_prompt=$(awk '/^---$/{c++; next} c==2' "$agent_file")

    local agent_out
    if ! agent_out=$(claude -p \
        --append-system-prompt "$agent_prompt
Respond as text only. Do not call any tools." \
        "$(cat "$input_file")" 2>&1); then
        err "$agent/$scenario: claude -p failed (agent run)"
        echo "$agent_out" >&2
        return 1
    fi
    echo "$agent_out" > "$scenario_dir/last_output.md"

    local judge_prompt
    judge_prompt="You are a strict eval judge. Given a rubric and an agent's response, decide which rubric items are met.

Output ONLY a single JSON object with keys:
  \"verdict\":  \"pass\" if ALL required (non-bonus) items met, else \"fail\"
  \"matched\":  array of rubric item numbers met
  \"missed\":   array of rubric item numbers missed
  \"notes\":    short string with reasoning

No prose outside the JSON.

=== RUBRIC ===
$(cat "$rubric_file")

=== AGENT RESPONSE ===
$agent_out"

    local verdict
    if ! verdict=$(claude -p "$judge_prompt" 2>&1); then
        err "$agent/$scenario: claude -p failed (judge run)"
        echo "$verdict" >&2
        return 1
    fi
    echo "$verdict" > "$scenario_dir/last_verdict.json"

    if echo "$verdict" | grep -q '"verdict"[[:space:]]*:[[:space:]]*"pass"'; then
        local matched_count
        matched_count=$(echo "$verdict" \
            | grep -oE '"matched"[[:space:]]*:[[:space:]]*\[[^]]*\]' \
            | grep -oE '[0-9]+' | wc -l | tr -d ' ')
        ok "$agent/$scenario  [$matched_count matched]"
        return 0
    else
        err "$agent/$scenario  → tests/$agent/$scenario/last_verdict.json"
        return 1
    fi
}

# --- Argument handling ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    grep -E '^# ?' "${BASH_SOURCE[0]}" | head -20 | sed 's/^# \{0,1\}//'
    exit 0
fi

preflight

if [[ "${1:-}" == "--list" || "${1:-}" == "-l" ]]; then
    echo "Discovered scenarios in $TESTS_DIR:"
    found=0
    for agent in $(list_agents_with_scenarios); do
        echo ""
        echo -e "  ${CYAN}$agent${NC}"
        for s in $(list_scenarios "$agent"); do
            echo "    - $s"
            found=$((found + 1))
        done
    done
    echo ""
    if [[ $found -eq 0 ]]; then
        warn "No scenarios. See docs/eval.md for the format."
    else
        info "$found scenario(s); a full run costs ~$((found * 2)) subscription messages"
    fi
    exit 0
fi

AGENT_FILTER="${1:-}"
SCENARIO_FILTER="${2:-}"

# Quick total before invoking claude — gives the user a heads-up.
total=0
for agent in $(list_agents_with_scenarios); do
    if [[ -n "$AGENT_FILTER" && "$agent" != "$AGENT_FILTER" ]]; then
        continue
    fi
    for s in $(list_scenarios "$agent"); do
        if [[ -n "$SCENARIO_FILTER" && "$s" != "$SCENARIO_FILTER" ]]; then
            continue
        fi
        total=$((total + 1))
    done
done

if [[ $total -eq 0 ]]; then
    if [[ -n "$AGENT_FILTER" || -n "$SCENARIO_FILTER" ]]; then
        warn "No matching scenarios for filter (agent='$AGENT_FILTER' scenario='$SCENARIO_FILTER')"
    else
        warn "No scenarios in $TESTS_DIR — see docs/eval.md to add some"
    fi
    exit 0
fi

info "Running $total scenario(s); ~$((total * 2)) subscription messages"

passed=0
failed=0

for agent in $(list_agents_with_scenarios); do
    if [[ -n "$AGENT_FILTER" && "$agent" != "$AGENT_FILTER" ]]; then
        continue
    fi
    scenarios=$(list_scenarios "$agent")
    [[ -z "$scenarios" ]] && continue

    matched_filter="no"
    for s in $scenarios; do
        if [[ -z "$SCENARIO_FILTER" || "$s" == "$SCENARIO_FILTER" ]]; then
            matched_filter="yes"; break
        fi
    done
    [[ "$matched_filter" == "yes" ]] || continue

    echo ""
    echo -e "${CYAN}═══ $agent ═══${NC}"

    for scenario in $scenarios; do
        if [[ -n "$SCENARIO_FILTER" && "$scenario" != "$SCENARIO_FILTER" ]]; then
            continue
        fi
        if run_scenario "$agent" "$scenario"; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done
done

echo ""
if [[ $failed -eq 0 ]]; then
    info "$passed/$((passed + failed)) passed (~$(((passed + failed) * 2)) messages used)"
else
    err  "$passed/$((passed + failed)) passed, $failed failed (~$(((passed + failed) * 2)) messages used)"
    exit 1
fi
