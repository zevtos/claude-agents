# doc2kb — Pitfalls (what NEVER to do)

## 1. Никогда не суммаризируй

Пользователь хочет **verbatim equivalent** того, что человек прочитал бы.
Суммаризация теряет факты, и потерянный факт не возвращается без
re-extraction (а исходный файл к тому моменту может быть недоступен).

Разрешено:
- структурная очистка (`normalize_md.py`) — дедупликация header/footer на
  >70% страниц, whitespace, ASCII control characters, известный boilerplate
  (Page X of Y, ©, "Click here…", "JavaScript required").

Запрещено:
- переписывание формулировок ("в ходе работы было…" → "сделано…"),
- абстрактные пересказы,
- удаление "избыточного" контента,
- перевод,
- объединение нескольких страниц в "summary".

## 2. Никогда не пропускай scout

Соблазн "у меня всего 3 PDF, просто прогоню extract" — это путь к тихим
ошибкам. Scout даёт оценку токенов, ловит encrypted и scanned файлы, и
батчит вопросы к пользователю в одно сообщение. Без scout вы:
- упустите encrypted PDF (extract_pdf_pymupdf4llm на нём упадёт),
- сохраните пустой Markdown из image-only PDF (см. пункт 3),
- не сможете оценить общий объём корпуса до начала работы.

## 3. Никогда не сохраняй пустой результат как успешный

Naive `pypdf.extract_text()` на сканированном PDF возвращает пустую строку
без exception. Каждый extract-скрипт ОБЯЗАН проверять минимальную длину
результата:
- `extract_pdf_pymupdf4llm.py` — `< pages * 30 chars` → warning.
- `extract_docx.py` — `< 50 chars` → warning.

Warnings попадают во frontmatter и в `manifest.json` — `build_manifest.py`
видит их и отражает в INDEX.

## 4. Никогда не embed-ь картинки как base64

DOCX часто содержит inline-images. По умолчанию `mammoth.convert_to_html`
эмбедит их как `<img src="data:image/png;base64,...">`. Это:
- катастрофически раздувает токены (одна диаграмма = десятки KB body),
- бесполезно для LLM — модель не видит пиксели в base64,
- ломает downstream-tooling, которое ожидает чистый Markdown.

`extract_docx.py` уже заменяет image_handler на placeholder
`<img src="" alt="image N: original alt text">`. Не переопределяйте это
поведение.

## 5. Никогда не игнорируй speaker notes в PPTX

Speaker notes в PowerPoint часто содержат больше семантики, чем слайды
(речь автора). Большинство alternative-конвертеров (`markitdown`,
`unstructured`) их теряют. `extract_pptx.py` всегда читает
`slide.notes_slide.notes_text_frame.text` и помещает их в раздел
`### Notes` под каждым слайдом.

## 6. Никогда не задавай пользователю серию вопросов

Если scout нашёл 3 encrypted PDF + 1 scanned PDF + 2 huge файла — это
ОДИН вопрос пользователю, не 6. Используй шаблон из
`references/batch-questions.md`. Иначе агент будет 6 раз останавливаться
и пользовательский опыт будет ужасным.

## 7. Никогда не используй `markitdown` или `unstructured` как замену

- `markitdown` теряет speaker notes в PPTX, теряет структуру таблиц в
  сложных DOCX, не делает encryption detection.
- `unstructured` в API/cloud-режиме отправляет данные наружу — это
  нарушает local-first принцип; localmode тяжёлый и менее точный, чем
  специализированные per-format экстракторы.

Per-format-best-tool stack (pymupdf4llm + mammoth + python-pptx + trafilatura)
даёт лучшее качество при минимальном bundle size.

## 8. Никогда не запускай heavy-tier extract без явного opt-in

(Это для follow-up commits, не для MVP.) `docling` тянет ~1 GB моделей с
HuggingFace; `marker-pdf` плюс модели — ещё столько же; `mlx-vlm` нужен
16+ GB RAM. Эти зависимости устанавливаются ТОЛЬКО при `DOC2KB_HEAVY=1`
или `DOC2KB_VLM=1` (см. `bootstrap.sh` в follow-up release).

## 9. Никогда не нормализуй имена/термины в исходном тексте

Сохраняй оригинальное написание. LLM лучше работает с реальными данными,
даже если автор написал "ВКР" в одном месте и "вкр" в другом, или
использует "—" вместо "-". Это семантически разные знаки и часто несут
информацию о стиле/контексте.

## 10. Никогда не сливай все файлы в один большой `corpus.md`

Per-source файлы + manifest — это и есть progressive disclosure. Один
большой файл проваливается в context rot на корпусах >100K токенов.
Структура `kb/docs/<id>-<slug>.md` уже даёт агенту во второй сессии
точечный доступ через `Grep`/`Read`.

## 11. Не доверяй расширению файла

`scout_corpus.py` всегда сверяет `python-magic` MIME с расширением. При
расхождении выставляет `mime_confidence: "low"` и добавляет warning. Это
важно для security (polyglot-файлы) и для корректности (когда пользователь
переименовал .docx в .pdf).

## 12. Не пиши binary content в kb/docs/*.md

Output файлы должны быть чистым UTF-8 Markdown. Никакого base64, никаких
binary blobs, никаких embedded fonts. Если extract-скрипт натолкнулся на
binary blob (chart, OLE object) — он добавляет placeholder типа `*(chart)*`
и warning в frontmatter.
