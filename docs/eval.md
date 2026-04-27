# Evaluating agent prompts

A small **local-only** harness for measuring whether an agent prompt actually does what the description claims. The runner is `scripts/eval.sh`; scenarios live under `tests/<agent>/<scenario>/`.

It uses the Claude Code CLI in headless mode (`claude -p`), which authenticates with whatever auth the user already has configured — typically a Claude.ai subscription via OAuth, **no API key needed**. Each scenario costs ~2 subscription messages: one for the agent, one for the LLM-as-judge step.

CI is intentionally not wired up. Running 9 agents × 5 scenarios on every PR would chew through quota for marginal benefit; iteration on agent prompts is a low-frequency, high-thought activity that warrants a manual run.

## Why this exists

Without an eval, "did this prompt change make `reviewer` better?" is unanswerable. You'd diff the markdown, eyeball it, ship, and only later notice in real usage that some quality dropped. With even three good scenarios per agent, you get a deterministic signal: prompt change → re-run eval → see which rubric items regressed.

## Architecture

```
┌─────────────┐    input.md     ┌──────────┐
│ scripts/    │ ──────────────▶ │ claude   │
│ eval.sh     │                 │ -p       │  ← agent under test
│             │ ◀────────────── │          │   (system prompt = agents/<name>.md body)
└─────────────┘    response     └──────────┘
        │
        │   rubric.md + agent response
        ▼
┌─────────────┐                 ┌──────────┐
│ judge       │ ──────────────▶ │ claude   │
│ prompt      │                 │ -p       │  ← LLM-as-judge
│             │ ◀────────────── │          │
└─────────────┘    JSON verdict └──────────┘
        │
        ▼
   pass / fail
```

The runner extracts the agent's system prompt from the body of `agents/<name>.md` (everything after the second `---` of the YAML frontmatter), injects it via `--append-system-prompt`, and sends `input.md` as the user message. The judge then receives the rubric + the agent's response and returns strict JSON.

## Adding a scenario

1. Create the folder: `mkdir -p tests/<agent>/<scenario>`. Agent name must match `agents/<agent>.md`. Scenario name is any human-readable ID like `sql_injection` or `negative_case_no_smell`.

2. Write `input.md` — the realistic user request. One scenario should test one behavior; don't pile ten unrelated bugs into one snippet.

3. Write `rubric.md` — a numbered list of what the agent **must** say, plus optionally:
   - Bonus items the agent gets credit for if it catches them.
   - Forbidden items the agent must NOT say (false positives).

4. Run: `bash scripts/eval.sh <agent> <scenario>`.

5. Inspect `tests/<agent>/<scenario>/last_output.md` (full agent response) and `last_verdict.json` (judge's structured verdict). Both are gitignored — they're for local debugging.

## Worked example: SQL injection

`tests/reviewer/sql_injection/input.md`:
````markdown
Review this Python module. Be concrete about what's wrong, where, and how to fix it.

```python
"""User-lookup endpoint."""
import sqlite3


def get_user_by_name(username):
    conn = sqlite3.connect("users.db")
    cursor = conn.cursor()
    query = f"SELECT id, email, password FROM users WHERE name = '{username}'"
    cursor.execute(query)
    return cursor.fetchone()


def login(username, password):
    user = get_user_by_name(username)
    if user and user[2] == password:
        return {"id": user[0], "email": user[1]}
    return None
```
````

`tests/reviewer/sql_injection/rubric.md`:
```markdown
Хороший review этого кода ОБЯЗАН отметить:

1. **SQL injection** — f-string в query, username подставляется как сырая
   строка. Должен предложить параметризованный запрос (`?` placeholder).
2. **Plain-text password storage** — пароли сравниваются как user[2] == password,
   явно хранятся в открытом виде. Должен сказать про bcrypt/argon2 hashing.
3. **Timing attack на сравнение паролей** — `==` уязвим к timing-атаке.
   Должен упомянуть hmac.compare_digest или константное сравнение.
4. **Connection не закрывается** — должен предложить `with sqlite3.connect(...)`.

Не должен (false positive):
- Не должен жаловаться на `import sqlite3` — это нормальная stdlib.
- Не должен предлагать менять архитектуру на ORM.
```

A typical successful run produces:
```
═══ reviewer ═══
✓ reviewer/sql_injection  [4 matched]
→ 1/1 passed (~2 messages used)
```

…and `last_verdict.json` looks like:
```json
{"verdict":"pass","matched":[1,2,3,4],"missed":[],"notes":"All four rubric items addressed: parameterized query example, bcrypt recommendation, hmac.compare_digest mention, with-statement for connection."}
```

## Writing rubrics that work

- **Be specific.** "Reviewer should mention security" is too vague; "Reviewer must mention SQL injection and propose parameterized queries" is checkable.
- **Number the items.** The judge returns matched/missed by index — easier to skim regressions.
- **Mark bonus items as bonus.** Otherwise the judge fails the scenario for missing nice-to-haves, and you stop trusting verdicts.
- **List forbidden items.** A reviewer that flags everything as "high severity" is broken; rubric should call this out.
- **Test negative cases too.** Add scenarios where the answer is "looks fine, no critical issues" — see if the agent over-flags.

## Sources of good scenarios

You don't have to write every scenario from scratch. Mine these for ideas:

- **OWASP Top 10 / CWE** examples for `security` and `reviewer`.
- **System Design Interview** style prompts for `architect` (capacity planning, partitioning, consistency tradeoffs).
- **Real PR comments** from open-source projects — pull recurring failure modes (race conditions, missing tests, unsafe migrations) and turn them into rubrics.
- **Postmortems** from publicly published outages (CloudFlare, AWS, GitHub status blogs) for `architect` and `dba` capacity scenarios.
- **Code golf / catastrophic failures** subreddits for amusing `refactorer` cases.

## Cost discipline

- `--list` is free (no claude call). Use it to audit before running.
- Run one scenario at a time during prompt iteration: `bash scripts/eval.sh <agent> <scenario>`.
- Run the full suite only when you're done iterating: `bash scripts/eval.sh`.
- 100 scenarios × 2 messages = 200 subscription messages, which on a Claude X20 sub is roughly 5–10% of a daily allowance.

## Limitations

- **Judge agreement isn't perfect.** Two different judge runs may disagree on borderline rubric items. For high-stakes prompts, run the same scenario 3× and look at consensus.
- **Stochasticity.** Agents are non-deterministic. A scenario that fails 1× then passes 2× isn't a clean regression — it's noise. Re-run.
- **Rubric drift.** Adding too many bonus items inflates pass rates. Periodically review what's bonus vs. required.
- **No model parameters exposed yet.** The runner uses whatever model `claude` defaults to. If you want to compare opus vs. sonnet on the same agent, you'd need to extend `eval.sh` with a `--model` flag and pass it through.

## Roadmap (not built yet)

- Multi-run averaging for noisy scenarios.
- Side-by-side diff view of two agent versions on the same suite.
- Agent-vs-agent comparison (e.g., is this prompt change actually a regression on `reviewer/code_review_basic` vs. baseline?).
- Programmatic rubrics (regex / required substring) for cheap deterministic checks alongside LLM-as-judge.
