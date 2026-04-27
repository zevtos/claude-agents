# tests/ — eval scenarios for agentpipe agents

Локальный тест-suite для агентов. **CI не подключен** — все прогоны делаются вручную через `bash scripts/eval.sh`, чтобы каждый PR не сжигал quota подписки.

Сейчас здесь нет ни одного сценария. Каркас пустой по дизайну: реальные тест-кейсы должны приходить из открытых источников (security CWE-примеры, code-review датасеты, prompt-engineering benchmarks) либо быть продуманы под конкретные слабости каждого агента — это не та работа, которую полезно делать в спешке.

Полный гайд: `docs/eval.md`.

## Структура

```
tests/
├── README.md                                          # этот файл
└── <agent>/                                           # имя совпадает с agents/<agent>.md
    └── <scenario>/                                    # любой человекочитаемый ID
        ├── input.md                                   # что отправляется агенту
        ├── rubric.md                                  # что должно быть в ответе
        ├── last_output.md      (gitignored)           # последний ответ агента
        └── last_verdict.json   (gitignored)           # последний вердикт судьи
```

`last_output.md` и `last_verdict.json` появляются после первого прогона и игнорируются git'ом — это локальные артефакты для дебага рубрик.

## Минимальный пример сценария

`tests/reviewer/sql_injection/input.md`:
```markdown
Review this Python module. Be concrete about what's wrong, where, and how to fix it.

​```python
def get_user(name):
    cursor.execute(f"SELECT * FROM users WHERE name = '{name}'")
    return cursor.fetchone()
​```
```

`tests/reviewer/sql_injection/rubric.md`:
```markdown
Хороший review этого кода ОБЯЗАН отметить:

1. **SQL injection** через f-string в query. Должен предложить параметризованный запрос с placeholder'ом.
2. **Отсутствие проверки типа username** — должен сказать про validation на границе.

Не должен (false positive):
- Не должен жаловаться на отсутствие type hints (out of scope для security review).
```

## Запуск

```bash
bash scripts/eval.sh --list                       # что есть, без вызова claude
bash scripts/eval.sh                              # всё подряд
bash scripts/eval.sh reviewer                     # только reviewer
bash scripts/eval.sh reviewer sql_injection       # одна штука
```

## Стоимость

Каждый сценарий = 2 сообщения подписки (вызов агента + вызов LLM-as-judge). Перед прогоном `eval.sh` печатает оценку.

## Что класть в `input.md`

То, что пользователь обычно даёт агенту в реальной работе: пример кода для review, спецификация для архитектора, схема БД для dba. Один сценарий проверяет одно поведение — не пихай в input десять разных проблем.

## Что класть в `rubric.md`

Чёткий список того, что агент **обязан** сказать (numbered), плюс опционально:
- **Бонус-пункты** — если упомянул, лучше; пропустил, не fail.
- **Запрещённое** — false positive'ы, которые сигналят что агент перебарщивает.

Судья получает рубрику + ответ агента и возвращает строгий JSON: `{"verdict": "pass|fail", "matched": [...], "missed": [...], "notes": "..."}`. Pass = все обязательные пункты найдены.
