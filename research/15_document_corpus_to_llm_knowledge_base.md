## Резюме и итоговое решение

# Skill для превращения сырого корпуса документов в LLM-оптимизированную базу знаний: исследовательский отчёт

## Краткое резюме (TL;DR)

**Архитектура.** Делайте skill в каноническом для Anthropic стиле (`SKILL.md` + `scripts/` + `references/` + `assets/`), с обязательной двухсессионной моделью: первая сессия (extraction) использует скрипты для скаутинга и извлечения, вторая сессия (working) потребляет компактную, иерархически организованную базу знаний. Skill должен следовать принципу progressive disclosure: лёгкая `description` во фронтматтере → подробный `SKILL.md` → справочные файлы и скрипты по требованию.

**Tech stack (local-first, macOS / Apple Silicon).**
- **PDF (native, text layer):** `pymupdf4llm` как первичный быстрый экстрактор → Markdown с заголовками, таблицами, картинками. `pdfplumber` — для сложных таблиц и точного layout. `pypdf` — для метаданных и манипуляций.
- **PDF (сложный layout, формулы, многоколонник):** `docling` (IBM, лучший out-of-the-box для RAG) или `marker-pdf` (Surya OCR, поддерживает MPS на Apple Silicon, флаг `--use_llm` для критичных документов).
- **PDF (сканы / image-only):** OCRmyPDF (обёртка над Tesseract) для добавления text layer; либо `pdf2image` + Tesseract / `RapidOCR` / `PaddleOCR`. Для топ-качества на M-series — VLM-маршрут: `mlx-vlm` + Qwen2-VL/DeepSeek-OCR/olmOCR-2/dots.ocr через MLX-квантизацию.
- **PDF (encrypted):** `pikepdf` для детекции (`PasswordError`) и попыток расшифровки с паролем от пользователя.
- **DOCX:** `mammoth` для чистого Markdown/HTML, либо `docling` для unified пайплайна. `python-docx` — для прямого доступа к структуре и обнаружения встроенных изображений.
- **PPTX:** `python-pptx` для прямого доступа к slide shapes, speaker notes (`slide.notes_slide.notes_text_frame.text`), таблицам и встроенным изображениям; либо `docling` (поддерживает PPTX).
- **XLSX/CSV:** `openpyxl` / `pandas`; для unified пайплайна `docling` или `markitdown`.
- **HTML/EPUB:** `trafilatura` (HTML→чистый Markdown), `ebooklib` для EPUB; `pandoc` как универсальный конвертер.
- **RTF/ODT:** `pandoc` через subprocess.
- **Изображения:** Tesseract / RapidOCR локально; для содержательного описания (а не только OCR) — VLM через `mlx-vlm` или прямое использование самого Claude в extraction-сессии для page-by-page чтения.
- **Sniffing / классификация:** `python-magic` (обёртка над libmagic) + Google `magika` как ML-fallback для сложных случаев.

**Формат вывода.** Markdown — основной носитель контента, JSON — для манифеста и метаданных. Каждый исходный файл превращается в отдельный `.md` файл; на верхнем уровне — `manifest.json` (источники, размеры в токенах, чанк-границы, флаги ошибок) и `INDEX.md` (читаемый агентом обзор). Иерархия: `kb/manifest.json` + `kb/INDEX.md` + `kb/docs/<slug>.md`. Используйте YAML-frontmatter в каждом `.md` с `source`, `sha256`, `pages`, `tokens`, `extraction_method`. Опционально — `kb/llms.txt` для совместимости с эмерджентным стандартом `llmstxt.org`.

**Главные ловушки, которых нужно избегать:**
1. Тихо извлекать "пустой" текст из скан-PDF — всегда детектируйте через порог символов на страницу и спрашивайте пользователя.
2. Перетаскивать в одну гигантскую markdown-простыню (context rot) — лучше per-source файлы + манифест.
3. Игнорировать speaker notes в PPTX (часто там вся семантика) и embedded images в DOCX/PPTX.
4. Использовать `python-docx` напрямую для Markdown — он не отдаёт чистую структуру; берите `mammoth` или `docling`.
5. Запускать тяжёлые ML-зависимости (`docling`, `marker-pdf`) по умолчанию на каждом файле — это медленно и съедает диск. Используйте tier-стратегию: дешёвый экстрактор сначала, тяжёлый — только когда дешёвый "проседает".

## 1. Состояние локальных библиотек извлечения (2024–2026)

## 1. Состояние локальных библиотек извлечения (2024–2026)

### 1.1 PDF — детальное сравнение

Рынок PDF-экстракторов в 2025–2026 разделён на четыре уровня по затратам ресурсов и качеству.

**Уровень 1: лёгкие, чисто на CPU, без ML.**
- **`pymupdf4llm`** — тонкая надстройка над PyMuPDF, отдаёт LLM-готовый Markdown с заголовками, таблицами, абзацами. Самый быстрый вариант: ~0.12 с на типовую страницу. Никаких моделей, никакого GPU, никаких heavy deps. Поддерживает page chunks (`page_chunks=True`) с метаданными на каждую страницу. Имеет встроенную детекцию страниц, нуждающихся в OCR. **Лучший дефолт для native PDF.** Слабая сторона — таблицы со сложным многоуровневым layout-ом извлекаются хуже, чем у docling.
- **`pdfplumber`** — отличная extraction таблиц (метод `extract_tables()`), детальный доступ к bbox и символам. Чистый текст требует тюнинга. Идеален как scout-инструмент: метод `extract_text()` плюс порог по числу символов на странице — лучший способ детектировать сканы.
- **`pypdf`** — pure-Python, без C-deps. Хорош для метаданных, склейки/разрезания, ротации. Низкого качества для экстракции текста с layout. Документация прямо предупреждает: «pypdf is no OCR software».
- **`pypdfium2`** — самая быстрая базовая extraction (микросекунды), но без какой-либо структуры.

**Уровень 2: layout-aware, лёгкая ML-обвязка.**
- **`docling`** (IBM Research, DS4SD) — выпущенный в 2024 фреймворк, в 2025 стал де-факто стандартом для RAG. Использует DocLayNet (layout analysis) и TableFormer (распознавание структуры таблиц). Поддерживает PDF, DOCX, PPTX, XLSX, HTML, изображения, аудио (WAV/MP3), LaTeX. Выдаёт `DoclingDocument` (внутренняя структура), сериализуемый в Markdown или JSON. Бенчмарки на отчётах устойчивого развития: 97.9% accuracy на сложных таблицах. Минусы: установка ~1 ГБ, требует загрузки моделей из HuggingFace, на CPU обработка одной страницы может занимать секунды. На Apple Silicon работает через MPS. **Лучший общий выбор, если терпимо отношение к размеру установки.**
- **`marker` / `marker-pdf`** (Vik Paruchuri) — конвертирует PDF, DOCX, PPTX, XLSX, HTML, EPUB в Markdown/JSON. Использует Surya OCR (свой движок). Поддерживает MPS на Apple Silicon. Флаг `--use_llm` опционально подключает LLM для повышения точности на критичных документах. Отлично работает на отсканированных книгах и многоязычных текстах. По скорости — медленнее `pymupdf4llm`, но выдаёт более структурированный результат.
- **`MinerU`** — специализирован на китайских, научных и финансовых документах с PaddleOCR. Хорошо распознаёт повёрнутые таблицы.
- **`unstructured`** — производит «семантические» чанки, удобные для RAG. Меньше акцента на полную верность Markdown, больше — на нарезку. Часто упоминается в LangChain/LlamaIndex стэке.

**Уровень 3: специализированные ML-модели.**
- **Nougat** (Meta) — научные статьи с формулами, выдаёт Markdown с LaTeX. Хорош для академических PDF, но узкоспециализирован.
- **GROBID** — стандарт для библиометрии (TEI XML output из научных статей), требует Java-сервер.
- **Smoldocling** (HuggingFace) — компактный (~256M params) OCR/layout model, оптимизирован под малый footprint. Подходит для batch.

**Уровень 4: VLM-based (вершина качества, конец 2025–начало 2026).**
Это новейшая категория: vision-language models, читающие страницу как изображение и выдающие структурированный Markdown.
- **DeepSeek-OCR** — релиз октябрь 2025, MIT license. На MacBook Pro M4 Max 128 GB с 8-битной MLX-квантизацией занимает ~5.5 GB памяти и обрабатывает ~32 страницы в секунду. На Mac Studio M3 Ultra можно запускать в 90 параллельных инстансах. Через `mlx-vlm` или PyTorch+MPS.
- **olmOCR-2-7B** (AllenAI, 2025) — Apache 2.0, есть MLX 4-bit квантизация (`richardyoung/olmOCR-2-7B-1025-MLX-4bit`), запускается через Ollama. Лидер OmniDocBench.
- **dots.ocr** (RedNote, 3B params) — на OmniDocBench обгоняет Gemini 2.5 Pro по сложной разметке; есть MLX-порты в комьюнити.
- **Qwen2-VL / Qwen2.5-VL** (через `mlx-vlm`) — универсальный VLM, хорош как fallback для page-by-page чтения.
- **MonkeyOCR-Apple-Silicon** — MonkeyOCR с MLX-VLM патчами под M-series.

**Pdf2image + OCR классика.** `pdf2image` → PIL → `pytesseract` / `easyocr` / `paddleocr` / `RapidOCR`. Tesseract — самый зрелый, требует системной установки (`brew install tesseract`). RapidOCR — самый удобный для интеграции (pure Python, ONNX-based). PaddleOCR — топ для не-латинских скриптов, но тяжёлый.

### 1.2 DOCX

- **`mammoth`** — конвертер DOCX → HTML/Markdown с акцентом на семантическую структуру (mapping styles to HTML/Markdown). **Лучший для чистого Markdown.** Игнорирует визуальное форматирование (что хорошо для LLM): отдаёт заголовки, списки, таблицы, без шума о цвете шрифта.
- **`python-docx`** — низкоуровневый доступ к структуре. Используйте его для:
  - детекции embedded images (`document.inline_shapes`, `document.part.related_parts`),
  - extraction таблиц с правильной структурой (`table.rows`, `cell.text`),
  - чтения header/footer (`section.header.paragraphs`),
  - детекции tracked changes, comments.
- **`docling`** — поддерживает DOCX в едином пайплайне; полезно если уже используется для PDF.
- **`markitdown`** (Microsoft) — лёгкая обёртка-конвертер для множества форматов в Markdown. Прост, быстр, но для DOCX даёт более «плоский» результат, чем mammoth/docling; теряет структуру таблиц на сложных документах.
- **`pandoc`** — внешний бинарь, конвертирует практически что угодно. Хорош как fallback для odt/rtf/docx, отдаёт качественный Markdown.

**Рекомендация:** `mammoth` для базовой конверсии в Markdown + `python-docx` для извлечения метаданных и обнаружения встроенных объектов в scout-фазе.

### 1.3 PPTX

- **`python-pptx`** — единственный нормальный pure-Python вариант. Доступ к:
  - shapes/text frames: `for shape in slide.shapes: if shape.has_text_frame: ...`
  - speaker notes: `slide.notes_slide.notes_text_frame.text`
  - таблицам: `shape.has_table` → `shape.table.rows`
  - embedded images: `shape.shape_type == MSO_SHAPE_TYPE.PICTURE` → `shape.image.blob`
  - comments (через прямой XML-парсинг pptx как zip).
- **`docling`** — поддерживает PPTX, удобно если уже в стеке.
- **`markitdown`** / **`unstructured`** — конвертируют PPTX в Markdown/чанки, но часто теряют speaker notes; всегда проверяйте на пилотных файлах.

**Критичный момент:** speaker notes в PPTX содержат до половины семантики презентации (рассказ автора). По умолчанию многие конвертеры их игнорируют. Скрипт-скаут должен проверять наличие notes (`has_notes_slide`) и помечать файлы с богатыми notes для специальной обработки.

### 1.4 Markdown / TXT

Тривиально, но не безопасно. Скрипт нормализации должен:
- определить кодировку (`chardet` или `charset-normalizer`),
- удалить BOM,
- нормализовать line endings (CRLF→LF),
- разобрать YAML/TOML frontmatter (хранить отдельно как метаданные),
- определить, нет ли «битой» структуры (например, mojibake — частая беда у файлов с macOS↔Windows-переходом).

### 1.5 Прочие форматы

- **XLSX/CSV:** `openpyxl` (XLSX), `pandas` (универсально, дёшево). Для LLM-вывода преобразовывайте таблицы в Markdown-таблицы или CSV-блоки. На очень широких таблицах JSON может быть компактнее.
- **HTML:** `trafilatura` — лучший экстрактор основного контента (boilerplate removal); затем `markdownify` или `html2text` для Markdown. `unstructured` тоже умеет.
- **EPUB:** `ebooklib` для разбора; затем HTML→Markdown через trafilatura.
- **RTF/ODT:** `pandoc` через subprocess — самый надёжный путь.
- **Изображения (PNG/JPG):** OCR через `RapidOCR`/Tesseract; для смысловых картинок — VLM-описание через MLX-VLM или сам Claude в extraction-сессии.
- **Код-файлы:** конкатенация с метаданными (язык, путь), либо специализированный инструмент типа `repomix`/`gitingest`. Если корпус включает много кода — лучше делегировать code-файлы в отдельный поток (см. секцию 7).

### 1.6 Head-to-head: markitdown vs docling vs unstructured

| Параметр | markitdown (Microsoft) | docling (IBM) | unstructured |
|---|---|---|---|
| Установка | ~50 MB | ~1 GB (с моделями) | ~200 MB+ |
| Скорость на PDF | Самая быстрая (text scrape) | Медленная (layout ML) | Средняя |
| Качество таблиц в PDF | Слабое | Лучшее (TableFormer ~97.9% на сложных) | Среднее (75% на сложных, 100% на простых) |
| Поддержка форматов | PDF, DOCX, PPTX, XLSX, изображения, аудио, ZIP | PDF, DOCX, PPTX, XLSX, HTML, изображения, аудио, LaTeX | Очень широкая (40+) |
| Семантические чанки | Нет | DoclingDocument (можно нарезать) | Да, ядро функционала |
| Лицензия | MIT | MIT | Apache 2.0 (с paid tier для API) |
| Apple Silicon | Полностью | MPS support | CPU |
| Best-for | Быстрый baseline | RAG-готовый Markdown с верной структурой | Семантические чанки для векторного поиска |

**Вывод:** «один инструмент для всего» — это **docling**, если терпимо размер установки. Но прагматичный подход — **per-format-best-tool**: `pymupdf4llm` для простых PDF, `docling`/`marker` для сложных, `mammoth` для DOCX, `python-pptx` для PPTX, `pandoc` для отступных форматов. Это даёт лучшее качество при минимуме оверхеда — и именно так устроены production-пайплайны RAG в 2025–2026.

## 2. Scout-скрипты: детекция и классификация

## 2. Scout-скрипты: детекция и классификация

Скаут-фаза — критическая часть skill. Её задача: до запуска тяжёлого извлечения построить точную карту корпуса, отметить «трудные» файлы, оценить стоимость и **запросить решение пользователя там, где автономный выбор небезопасен**.

### 2.1 Детекция PDF с/без text layer

Канонический алгоритм (рекомендуется индустрией):

```python
import pdfplumber

def classify_pdf(path: str, char_threshold: int = 100):
    """Returns one of: 'text', 'image_only', 'mixed', 'encrypted', 'corrupt'."""
    try:
        with pdfplumber.open(path) as pdf:
            n_pages = len(pdf.pages)
            text_pages = 0
            for page in pdf.pages:
                txt = page.extract_text() or ""
                if len(txt.strip()) >= char_threshold:
                    text_pages += 1
            if text_pages == 0:
                return "image_only", {"pages": n_pages, "text_pages": 0}
            if text_pages < n_pages * 0.5:
                return "mixed", {"pages": n_pages, "text_pages": text_pages}
            return "text", {"pages": n_pages, "text_pages": text_pages}
    except Exception as e:
        if "password" in str(e).lower() or "encrypt" in str(e).lower():
            return "encrypted", {"error": str(e)}
        return "corrupt", {"error": str(e)}
```

Порог 100 символов на страницу — общепринятый. Для разреженных научных слайдов (где каждая страница реально содержит мало текста) можно опустить до 50 или дополнительно проверить отношение текст/изображения через `page.images`.

Альтернатива: использовать `pymupdf4llm` с его встроенной "automatic detection of pages which profit from OCR" — он сам помечает страницы, нуждающиеся в OCR.

### 2.2 Детекция encrypted/protected PDF

Лучший инструмент — `pikepdf` (обёртка над qpdf):

```python
import pikepdf
def check_encrypted(path: str):
    try:
        pdf = pikepdf.open(path)
        return {"encrypted": False, "permissions": None}
    except pikepdf.PasswordError:
        return {"encrypted": True, "needs_password": True}
    except Exception as e:
        return {"encrypted": "unknown", "error": str(e)}
```

`pikepdf.Pdf.open(path, password='...')` — поддерживает AES-256/AES-128/RC4. Для DOCX/XLSX с паролем — библиотека **`msoffcrypto-tool`** (поддерживает Office 97–2019).

**Решение пользователя.** Скаут возвращает структурированный JSON: `{path, type: "encrypted", action_required: "ask_user_password_or_skip"}`. SKILL.md должен инструктировать агента: при наличии encrypted-файлов остановиться и сформировать единый блок вопросов к пользователю (одним сообщением: "У вас 3 зашифрованных файла. Что делать: (a) пропустить все, (b) дать пароль для каждого, (c) попробовать общий пароль...").

### 2.3 Детекция «богатых» DOCX/PPTX

```python
from docx import Document
def docx_richness(path):
    doc = Document(path)
    return {
        "paragraphs": len(doc.paragraphs),
        "tables": len(doc.tables),
        "inline_images": len(doc.inline_shapes),
        "has_headers": any(s.header.is_linked_to_previous is False for s in doc.sections),
        "has_footnotes": "footnoteReference" in doc.element.xml,
        "has_comments": "commentReference" in doc.element.xml,
        "has_equations": "<m:oMath" in doc.element.xml,  # OOXML math
        "tracked_changes": "w:ins" in doc.element.xml or "w:del" in doc.element.xml,
    }

from pptx import Presentation
def pptx_richness(path):
    p = Presentation(path)
    has_notes_any = False; total_notes_chars = 0; n_images = 0; n_tables = 0
    for slide in p.slides:
        if slide.has_notes_slide:
            t = slide.notes_slide.notes_text_frame.text
            if t.strip(): has_notes_any = True; total_notes_chars += len(t)
        for sh in slide.shapes:
            if sh.shape_type == 13: n_images += 1  # PICTURE
            if sh.has_table: n_tables += 1
    return {"slides": len(p.slides), "has_notes": has_notes_any,
            "notes_chars": total_notes_chars, "images": n_images, "tables": n_tables}
```

Эти метрики попадают в манифест и используются для выбора стратегии: если `pptx.has_notes` и `notes_chars > 1000` — обязательно extract notes и поместить рядом со слайдами в Markdown; если `docx.inline_images > 5` — пометить файл как требующий VLM-описания картинок.

### 2.4 File-type sniffing

**Никогда не доверяйте расширению файла.** Стандартный pipeline:

1. **`python-magic`** (обёртка над libmagic) — детекция через magic bytes. На macOS требует `brew install libmagic`. Возвращает MIME-тип.
2. **Google `magika`** — ML-based детектор (выпущен Google в 2024), тренирован на ~100M файлов, точнее `libmagic` на спорных случаях. Использовать как fallback при low-confidence из libmagic.
3. Skill должен сначала вызывать `file --mime-type` (системную) либо `magic.from_file(path, mime=True)`, потом сверять с расширением, и при расхождении логировать.

Простая логика:

```python
import magic
def sniff(path):
    mime = magic.from_file(path, mime=True)
    desc = magic.from_file(path)
    return {"mime": mime, "desc": desc}
```

Известный «подводный камень» (см. CTBB lab): libmagic можно обмануть глубоко вложенным JSON, и polyglot-файлы могут давать ложное определение. Это релевантно для security-critical контекстов, но для skill-а можно жить с этим — главное помечать `confidence: low` если есть расхождение mime ↔ extension.

### 2.5 Оценка стоимости и сложности заранее

Скаут должен прикинуть **token budget** до начала извлечения. Формула:

- **PDF:** ~500–800 токенов на страницу для density текста; ~250 для разреженных слайдов; ~2000+ для tables-heavy.
- **DOCX:** ~1 токен на 3.5 символа (≈ англ.) или 2 (рус.). Берите char count / 3 как грубую оценку.
- **PPTX:** ~150–400 токенов на слайд (без notes) + объём notes.

Скрипт `scout_corpus.py` должен выдавать единый JSON-отчёт:

```json
{
  "corpus": {
    "total_files": 47,
    "total_size_bytes": 184392012,
    "estimated_tokens": 1240000,
    "estimated_extraction_time_seconds": 420
  },
  "files": [
    {
      "path": "papers/transformer.pdf",
      "mime": "application/pdf",
      "size": 1240393,
      "pages": 12,
      "pdf_class": "text",
      "extraction_strategy": "pymupdf4llm",
      "estimated_tokens": 7200,
      "warnings": []
    },
    {
      "path": "scans/old_textbook.pdf",
      "mime": "application/pdf",
      "size": 84219201,
      "pages": 412,
      "pdf_class": "image_only",
      "extraction_strategy": "needs_ocr_or_vlm",
      "estimated_tokens": null,
      "warnings": ["scanned: ask user", "very large: 412 pages"]
    },
    {
      "path": "lectures/intro.pptx",
      "mime": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      "size": 5210493,
      "slides": 48,
      "has_notes": true,
      "notes_chars": 12400,
      "extraction_strategy": "python-pptx+vlm-for-images",
      "estimated_tokens": 18000,
      "warnings": ["rich speaker notes — include"]
    },
    {
      "path": "contracts/nda.pdf",
      "pdf_class": "encrypted",
      "action_required": "ask_user_password_or_skip"
    }
  ],
  "user_decisions_needed": [
    {"type": "encrypted", "files": ["contracts/nda.pdf"], "options": ["password","skip"]},
    {"type": "scanned", "files": ["scans/old_textbook.pdf"], "options": ["ocr_tesseract","vlm_mlx","claude_pagewise","skip"]}
  ]
}
```

Этот JSON — основа для всех решений на следующих фазах.

## 3. Оптимальный формат вывода для LLM/агента

## 3. Оптимальный формат вывода для LLM/агента

### 3.1 Markdown vs JSON vs JSONL vs XML

Консенсус 2025–2026: **Markdown — основной носитель содержания, JSON — для метаданных и манифеста.** Аргументы:

- **Эффективность токенов.** Исследования показывают: Markdown сокращает токены до 80% по сравнению с эквивалентным HTML; «AI-friendly» формат давал ~30% сокращение токенов при ~7% росте accuracy в одном бенчмарке. Эссе E. M. Freeburg «The Last Fingerprint» (март 2026) утверждает, что современные LLM «думают в Markdown» — структурные сигналы (заголовки, списки, fenced code) воспринимаются как «родные».
- **Семантические чанки.** Markdown заголовки (`##`, `###`) дают естественные boundary для chunking — это даёт до 35% прироста retrieval accuracy в RAG по сравнению с naive splitting. NVIDIA bench (2024) показал, что page-level chunking даёт лучшую точность.
- **JSON для строгих данных.** JSON оптимален для манифестов, schema-driven данных, таблиц с фиксированной структурой. JSONL хорош для построчного потокового чтения, но плохо подходит для содержательных документов (LLM «теряется» в полях).

**Не используйте XML для контента.** Anthropic'овский собственный pattern `<example>...</example>` в промптах — это для разделения секций в инструкциях, а не для содержимого знаний.

### 3.2 Anthropic-специфичные ориентиры

Из официальных гайдов Anthropic и Claude Code:
- Skill сам по себе — это Markdown (`SKILL.md`) с YAML-frontmatter; это формат, с которым Claude работает «нативно».
- Pre-built skill `pdf` от Anthropic в качестве вывода рекомендует Markdown-плоский текст из `pypdf`/`pdfplumber`.
- Anthropic's «Effective context engineering for AI agents» (статья 2025) явно рекомендует: давать агенту **навигируемую файловую систему** с осмысленными именами и манифестом, а не одну огромную простыню — это и есть progressive disclosure.
- Cloudflare и другие документ-вендоры публикуют контент в Markdown по запросу `Accept: text/markdown`; собственные `/llms.txt` и `/llms-full.txt` — формальное признание того, что LLM лучше потребляют Markdown с явным индексом.

### 3.3 Организация многофайловой базы знаний

Рекомендуемая иерархия:

```
kb/
├── manifest.json          # Машинно-читаемый индекс: пути, токены, провенанс, ошибки
├── INDEX.md               # Агент-читаемый "оглавление": краткое описание корпуса
├── llms.txt               # (опционально) llmstxt.org-совместимый индекс
├── docs/
│   ├── <source-slug-1>.md
│   ├── <source-slug-2>.md
│   └── ...
├── assets/                # (опционально) Извлечённые картинки, если решено сохранить
│   └── <hash>.png
└── _logs/
    ├── extraction.log
    └── errors.json
```

**Почему не один файл.** «LLM wiki» в одном Markdown-файле — приемлемо для < 100K токенов. На больших корпусах он провоцирует context rot: модель теряет точность на материале в середине большого контекста. Per-source файлы + манифест позволяют агенту читать только релевантное (тот же principle, что Claude Code skills используют: загрузить лёгкое описание сначала, полный контент потом).

**Почему манифест.** Агент во второй (working) сессии читает сначала `manifest.json` (~2–5K токенов даже для большого корпуса), затем по необходимости открывает конкретные `docs/*.md` через `Read`/`Grep`. Это и есть применение progressive disclosure к самой базе знаний.

### 3.4 Структура отдельного `.md` файла

```markdown
---
source: /Users/me/docs/papers/transformer.pdf
source_type: pdf
source_sha256: a4f...91
pages: 12
extraction_method: pymupdf4llm@0.0.20
extraction_date: 2026-05-16
tokens_estimated: 7200
warnings: []
---

# Attention Is All You Need

## §1 Introduction
...

## §2 Background
...

[page 5]
| col1 | col2 |
| --- | --- |
| ... | ... |

[page 7]
![figure-2](assets/transformer-arch-a4f91.png)
*VLM caption: Diagram of transformer encoder-decoder with multi-head attention block.*
```

Ключевые принципы:
- **Frontmatter с провенансом** — каждый чанк/файл носит ссылку на источник. Это важно для агента, чтобы он мог сослаться на источник в выводе.
- **Page anchors** (`[page N]`) — лёгкие, неинвазивные, дают агенту способ ссылаться на конкретные страницы.
- **Headings = chunk boundaries** — нумерованные семантические разделы (`## §1`, `## §2`) дают чёткую структуру.
- **Картинки**: либо сохраняйте отдельно (`assets/`) с inline ссылкой и VLM-caption, либо описывайте inline и не сохраняйте бинарь. Для агентов **VLM-caption inline** обычно достаточно (нужно семантическое описание, а не сам пиксель).
- **Таблицы** — Markdown-таблицы оптимальны для маленьких/средних; для очень широких таблиц лучше CSV-fenced код-блок или JSON-блок.

### 3.5 Структура `manifest.json`

```json
{
  "version": "1.0",
  "created_at": "2026-05-16T12:00:00Z",
  "extraction_tool": "doc2kb-skill@0.1.0",
  "corpus_root": "/Users/me/docs",
  "total_documents": 47,
  "total_tokens_estimated": 1240000,
  "documents": [
    {
      "id": "doc-001",
      "source_path": "papers/transformer.pdf",
      "kb_path": "docs/transformer.md",
      "sha256": "a4f...91",
      "size_bytes": 1240393,
      "source_type": "pdf",
      "extraction_method": "pymupdf4llm",
      "tokens_estimated": 7200,
      "pages": 12,
      "headings": ["Introduction","Background","Model Architecture","Results"],
      "has_tables": true,
      "has_images": true,
      "warnings": []
    }
  ],
  "skipped": [
    {"source_path": "contracts/nda.pdf", "reason": "encrypted, user skipped"}
  ],
  "errors": []
}
```

### 3.6 Структура `INDEX.md` (читается агентом первым)

```markdown
# Knowledge Base Index

47 documents extracted on 2026-05-16. Estimated total: ~1.24M tokens.

## How to use
1. Read this file first to understand the corpus.
2. Read `manifest.json` for machine-readable metadata.
3. Open individual files in `docs/` only as needed.

## By topic
- **Transformer architectures** — `docs/transformer.md`, `docs/bert.md`, `docs/gpt2.md`
- **Optimization** — `docs/adam.md`, `docs/sgd-momentum.md`
- **Lecture notes** — `docs/lecture-01-intro.md` … `docs/lecture-12-rnn.md`

## By source type
- PDF (papers): 23
- PPTX (lectures): 12
- DOCX (assignments): 8
- MD (own notes): 4
```

Сам skill (в фазе extraction) генерирует `INDEX.md` с группировкой по эвристике (по headings из манифеста, по типу источника, по дате). Это даёт агенту во второй сессии быстрый обзор.

### 3.7 Token efficiency — конкретные приёмы

- **Удаление повторяющихся header/footer.** Скаут детектирует одинаковую строку на >70% страниц PDF — это header/footer; убирайте.
- **Сжатие whitespace.** Множественные пустые строки → одна.
- **Удаление номеров страниц как отдельных строк** (если они уже в page anchors).
- **Boilerplate.** Удалять стандартные «© Confidential», лицензионные хвосты, JavaScript-сообщения «Please enable JavaScript».
- **Не использовать жирный/курсив без семантики.** Многие экстракторы наследуют Word-стили (`**bold**`) на оформительских участках; для LLM это шум.
- **НЕ суммаризируйте контент.** Это сильное предупреждение: пользователь хочет «эквивалент того, что человек прочитал все файлы», то есть verbatim equivalence. Summarization рискует потерять факты, которые потом окажутся нужны. Сжимайте через дедупликацию и удаление шума, но не через переписывание.

### 3.8 Эмерджентные стандарты: llms.txt и AGENTS.md

- **`llms.txt`** (llmstxt.org) — спецификация для веб-сайтов: Markdown-файл в корне с indexed списком ссылок. Принят Anthropic, OpenAI, Cloudflare, Fern, многими docs-движками. **Для skill-а уместно** генерировать `llms.txt` в корне `kb/` как дополнительный индекс — это даёт совместимость с инструментами типа `llms_txt2ctx` и эстетически приятный формат.
- **`AGENTS.md`** (agents.md, под Linux Foundation / Agentic AI Foundation с 2025) — стандарт для **репозитория с кодом** для агентских coding-tools (Codex, Cursor, Claude Code, Jules). Это **не формат для базы знаний**, это формат конфигурации проекта. Но если skill используется для подготовки контекста к coding-сессии, имеет смысл включать `AGENTS.md` в корень kb/ с инструкцией для второй сессии, как читать манифест.

**Рекомендация:** генерировать оба — `llms.txt` (как catalog базы знаний) и краткий `AGENTS.md` (как инструкция для агента, ниже про устройство папки).

## 4. Архитектура skill и best practices Claude Code

## 4. Архитектура skill и best practices Claude Code

### 4.1 Каноническая структура skill

По официальной документации Anthropic (`platform.claude.com/docs/en/agents-and-tools/agent-skills/overview`) и `anthropics/skills` repo:

```
doc2kb/
├── SKILL.md                # Required: YAML frontmatter + Markdown body
├── references/             # Loaded on demand
│   ├── extraction-recipes.md
│   ├── format-spec.md      # Спецификация выходного формата
│   └── pitfalls.md
├── scripts/                # Detеrministic code, runs via Bash tool
│   ├── bootstrap.sh        # Создаёт venv, ставит deps на первом запуске
│   ├── scout_corpus.py     # Полный сканер
│   ├── classify_pdf.py
│   ├── check_encrypted.py
│   ├── docx_richness.py
│   ├── pptx_extract.py
│   ├── extract_pdf_pymupdf4llm.py
│   ├── extract_pdf_docling.py
│   ├── extract_pdf_marker.py
│   ├── extract_with_vlm.py     # MLX-VLM page-by-page
│   ├── normalize_md.py
│   ├── build_manifest.py
│   └── token_count.py          # tiktoken/anthropic-tokenizer
├── assets/                 # Шаблоны: пустой manifest.json, INDEX.md
│   ├── manifest_template.json
│   └── index_template.md
└── .venv/                  # Создаётся при первом запуске; в .gitignore
```

### 4.2 Frontmatter и body SKILL.md

Anthropic best practices:
- `name`: ≤ 64 символа, нижний регистр, цифры, дефисы.
- `description`: ≤ 1024 символа, должно быть **«push»**-описанием (Claude склонна «undertrigger» skills — описание должно явно перечислять триггерные термины).
- Тело SKILL.md: ≤ 500 строк (~1500–2000 слов). Всё детальное — в `references/`.

Пример:

```yaml
---
name: doc2kb
description: |
  Converts a heterogeneous corpus of raw documents (PDF including
  scanned/encrypted, DOCX, PPTX, MD, TXT, XLSX, HTML, EPUB, images) into a
  structured, LLM-optimized knowledge base in a separate extraction session.
  USE THIS SKILL WHENEVER the user asks to ingest, index, prepare, preprocess,
  or build a knowledge base from a folder of mixed documents, prepare files
  for another Claude session, or convert a document corpus to markdown.
  Also use when the user mentions "RAG prep", "doc corpus", "feed files to
  Claude", or has a folder with many file types and wants them ready for an
  agent.
license: MIT
---

# doc2kb — Document Corpus → LLM Knowledge Base

## When to use
Use when the user has a folder of mixed-format documents and wants them
converted into a compact, structured knowledge base that another Claude (or
Codex) session can ingest as context. The output is for AI agents — not for
human reading.

## Workflow (4 phases)
1. **Bootstrap**: ensure venv exists; install missing deps.
2. **Scout**: run `scripts/scout_corpus.py <input_dir> <kb_dir>`. It produces
   `kb/_scout.json` describing every file and listing user decisions needed.
3. **Decide**: read `_scout.json`. If `user_decisions_needed` is non-empty,
   STOP and ask the user in ONE message (batch all questions). Common
   decisions: encrypted PDFs (skip/password), scanned PDFs (skip/ocr/vlm/
   claude-pagewise), huge files (skip/process).
4. **Extract**: for each file, route to the right script based on
   `extraction_strategy` in scout output. See `references/extraction-recipes.md`.
5. **Assemble**: run `scripts/build_manifest.py <kb_dir>` to generate
   `manifest.json`, `INDEX.md`, `llms.txt`.

## Critical rules
- NEVER summarize or rewrite content. Preserve verbatim with structural cleanup
  only (deduplication, whitespace, boilerplate). See `references/pitfalls.md`.
- ALWAYS ask user before processing scanned PDFs (OCR/VLM is expensive).
- ALWAYS report extraction errors in `_logs/errors.json`, don't silently skip.
- Each output .md file MUST have YAML frontmatter with source path, sha256,
  extraction_method, and tokens_estimated.

## Output format
See `references/format-spec.md` for the full specification.

## Scripts inventory
- `bootstrap.sh` — first-run venv + deps install. Idempotent.
- `scout_corpus.py <input> <kb>` — scan and classify. Outputs _scout.json.
- `extract_pdf_pymupdf4llm.py <pdf> <out.md>` — fast native PDF.
- `extract_pdf_docling.py <pdf> <out.md>` — layout-aware, for complex PDFs.
- `extract_pdf_marker.py <pdf> <out.md>` — for scanned/OCR.
- `extract_with_vlm.py <pdf> <out.md> --model qwen2-vl` — VLM page-by-page.
- `extract_docx.py <docx> <out.md>` — mammoth + python-docx.
- `extract_pptx.py <pptx> <out.md>` — python-pptx, includes speaker notes.
- `extract_office_other.py <file> <out.md>` — pandoc fallback.
- `normalize_md.py <md>` — dedupe headers/footers, strip boilerplate.
- `build_manifest.py <kb>` — assemble manifest.json, INDEX.md, llms.txt.
- `token_count.py <md>` — estimate tokens (tiktoken / anthropic).
```

### 4.3 Двухсессионный workflow

**Сессия 1 (extraction).** Открывается в любой папке с корпусом. Пользователь говорит «обработай эту папку». Claude обнаруживает skill `doc2kb` через description, читает SKILL.md, запускает scout, общается с пользователем по непонятным файлам, запускает extraction, собирает kb/.

**Сессия 2 (working).** Открывается с `kb/` как working directory (или с symlink на kb/). Здесь два варианта:

**A) Без второго skill** (рекомендуется для начала). В `kb/AGENTS.md` (или `kb/CLAUDE.md`) — короткая инструкция:
```markdown
# Knowledge Base

Read `INDEX.md` first to see what is in this corpus.
Read `manifest.json` for machine-readable metadata.
Open individual files in `docs/` only when needed — do NOT bulk-load.

Each doc has YAML frontmatter with `source` (original path).
When citing facts, reference the source path.
```
Claude Code сам прочитает CLAUDE.md/AGENTS.md в начале сессии.

**B) Парный «reader» skill** `doc2kb-reader` — у которого SKILL.md просто инструктирует, как навигировать kb/. Полезно если пользователь часто работает с такими kb-папками и хочет, чтобы Claude автоматически активировал нужный паттерн. Это и есть pattern «two skills» из обсуждения Anthropic engineering blog.

### 4.4 venv bootstrap pattern

`bootstrap.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="$SKILL_DIR/.venv"
PY=python3

if [ ! -d "$VENV_DIR" ]; then
  "$PY" -m venv "$VENV_DIR"
fi
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

pip install --quiet --upgrade pip
pip install --quiet \
  pymupdf4llm pdfplumber pypdf pikepdf python-magic \
  python-docx mammoth python-pptx openpyxl pandas \
  trafilatura ebooklib markdownify \
  rapidocr-onnxruntime \
  tiktoken \
  charset-normalizer

# Heavy deps — install only if user opted in (env DOC2KB_HEAVY=1)
if [ "${DOC2KB_HEAVY:-0}" = "1" ]; then
  pip install --quiet docling marker-pdf
fi

# VLM deps — only if DOC2KB_VLM=1 (Apple Silicon: brew install required)
if [ "${DOC2KB_VLM:-0}" = "1" ]; then
  pip install --quiet mlx-vlm
fi

echo "doc2kb venv ready at $VENV_DIR"
```

В каждом extraction-скрипте — shebang `#!/usr/bin/env -S bash -c '"$(dirname "$0")"/../.venv/bin/python "$0" "$@"'` или просто инструкция в SKILL.md: «всегда вызывай `bash scripts/bootstrap.sh && .venv/bin/python scripts/<name>.py ...`».

### 4.5 Возврат структурированного JSON из скриптов

Все scout/extraction скрипты должны возвращать JSON в stdout (а не plain текст). Это даёт агенту возможность рассуждать о результате:

```bash
$ .venv/bin/python scripts/classify_pdf.py /path/to/x.pdf
{"path":"/path/to/x.pdf","pdf_class":"image_only","pages":42,...}
```

При extraction скрипт записывает Markdown на диск и в stdout возвращает {"ok":true,"out":"kb/docs/x.md","tokens_estimated":4200,"warnings":[]}.

### 4.6 Обработка edge cases

| Случай | Действие |
|---|---|
| Encrypted PDF | Scout помечает, агент спрашивает пользователя; `pikepdf.open(password=...)` |
| Password-protected DOCX/XLSX | `msoffcrypto-tool` для проверки и расшифровки |
| Corrupt PDF | Попытка через `pikepdf` `--repair` (qpdf поддерживает repair); если не работает — лог в `errors.json`, пропуск |
| Unknown format | python-magic + magika; если оба не уверены — пропуск с warning |
| Огромный файл (>50 MB или >500 страниц) | Scout помечает; агент спрашивает «процессить целиком / по частям / пропустить» |
| Image-only PDF | Спросить пользователя: Tesseract (быстро, средне) / MLX-VLM (медленно, точно) / Claude page-by-page (дорого по токенам, очень точно) / skip |
| Битая кодировка txt | `charset-normalizer`; при низкой confidence — пропуск с warning |
| Files-to-prompt сценарий (много кода) | Делегировать `repomix`/`gitingest` через subprocess для кодовых поддиректорий |

### 4.7 Когда спрашивать пользователя vs действовать автономно

**Спросить:**
- Encrypted/password-protected files.
- Image-only PDF > 5 страниц (выбор стратегии OCR).
- Файлы >50 MB / >500 страниц.
- Файлы с непонятным/расходящимся MIME-type.
- Если общий estimated_tokens > какого-то порога (например, 500K) — предложить выбрать поджмножество.

**Действовать автономно:**
- Native PDF с text layer — извлекать через pymupdf4llm.
- DOCX/PPTX с явной структурой — извлекать без вопросов.
- md/txt — нормализовать и копировать.
- Файлы с известными ошибками extraction — логировать и пропускать.

**Pattern:** один вопрос пользователю в виде batch — список решений с дефолтами:
```
Я отсканировал корпус и нашёл:
- 3 зашифрованных PDF: contracts/{a,b,c}.pdf  → [пропустить / дать пароль]
- 1 PDF-скан (412 страниц): scans/textbook.pdf → [skip / tesseract-ocr / mlx-vlm / claude-pages]
- 2 файла >100 MB → [skip / proceed]

Ответьте одним сообщением, например: 'a: skip; b,c: <password>; textbook: tesseract-ocr; big: proceed'
```

## 5. Сжатие и информационная плотность

## 5. Сжатие и информационная плотность

### 5.1 Что значит «сжать без потерь» для LLM

Цель — сохранить **семантическую эквивалентность сырому файлу** при минимуме токенов. Это не классическая компрессия (gzip) и не классическая суммаризация. Это **структурная очистка**: убрать всё, что **не несёт информации, которую человек получил бы при прочтении**.

### 5.2 Конкретные техники

1. **Дедупликация header/footer.** На PDF с одинаковой строкой на >70% страниц — это шапка/подвал. Удалять. Экономия 5–15% токенов на типовых отчётах.
2. **Удаление визуального форматирования.** `**bold**` без семантической функции (то есть когда жирный — это просто стиль абзаца, а не выделение термина) → обычный текст. Курсив тот же. Это особенно про DOCX-конверсию через mammoth.
3. **Свёртка whitespace.** Множественные пустые строки → 1; trailing whitespace → удалить; tabs внутри текста → пробел.
4. **Нормализация символов.** «Умные» кавычки → ASCII; «en dash»/«em dash» оставить только если они в тексте, не в декорации; вычистить нулевые символы и control characters.
5. **Удаление номеров страниц как отдельных строк**, если они уже инкорпорированы в `[page N]` anchors.
6. **Boilerplate detection.** Маленькие фрагменты вроде «© 2024 Acme Inc. Confidential.», «Page X of Y», «Click here to view online», «JavaScript required» — паттерны, которые ловятся регулярками.
7. **Удаление повторяющихся слайд-шаблонов** в PPTX (логотип на каждом слайде, дата в footer).
8. **Сжатие таблиц.** Очень широкие таблицы с разрежёнными данными — представлять как CSV-блок (меньше токенов на разметку). Для маленьких таблиц — Markdown оптимален.
9. **Картинки → подпись.** Если в исходном файле картинка, и в подписи (caption/alt) уже есть текст, описывающий её — использовать caption и не запускать VLM. Если caption отсутствует и картинка содержательная — короткая VLM-генерируемая подпись (10–30 слов) на порядки дешевле, чем сохранение пикселей в base64.
10. **Удаление избыточных reference-секций.** В научных PDF библиографии могут составлять 10–20% содержимого. Если пользователь не работает с цитированиями — опционально удалить (с флагом в frontmatter `references_stripped: true`).

### 5.3 Что НЕ делать

- **Не суммаризировать.** Пользователь явно просит «эквивалент тому, что человек прочитал все файлы». Суммаризация теряет факты, и факты, которые потерялись, потом не вернёшь без re-extraction.
- **Не агрессивно резать «boilerplate»** без regexp-уверенности — есть риск выкинуть подзаголовок.
- **Не нормализовать имена/термины.** Сохраняйте оригинальное написание; LLM лучше работает с реальными данными.
- **Не сливать главы в один большой блок** — структурные boundaries (заголовки) полезны для retrieval.

### 5.4 Бенчмарки и ожидаемое сжатие

Грубые ориентиры из практики (на типичном смешанном корпусе):
- DOCX → Markdown через mammoth: -10% к -30% символов (удаление XML-обвязки).
- PDF → Markdown через pymupdf4llm: ~эквивалентно по содержанию, но удаление header/footer + boilerplate даёт -10% к -20%.
- PPTX → Markdown через python-pptx + notes: +20% к +40% (потому что speaker notes часто длиннее самих слайдов) — это **не сжатие, а раскрытие**: пользователь забывает, что в PPTX половина текста спрятана.
- HTML → Markdown через trafilatura: -50% к -80% (вычищается весь nav/footer/ads).

### 5.5 Token counting

Скрипт `token_count.py` должен использовать:
- `tiktoken` с `cl100k_base` — приемлемый proxy для Claude/GPT-4 (различие 5–10%).
- `anthropic` SDK — точный counter для Claude, если установлен.
- Простая эвристика fallback: `len(text) / 3.5` для англ., `len(text) / 2` для рус. (минимальный модуль).

Знать токены критично, чтобы манифест и INDEX могли показать пользователю «общий объём корпуса ~1.24M токенов, не влезет в один контекст, рекомендую читать по частям».

## 6. Конкретные рекомендации и blueprint

## 6. Конкретные рекомендации и blueprint

### 6.1 Финальный tech stack (macOS, local-first)

| Слой | Технология | Зачем |
|---|---|---|
| Runtime | Python 3.11+ в локальном `.venv` внутри skill | Изоляция, без загрязнения системы |
| Sniffing | `python-magic` (+ `brew install libmagic`) | MIME через magic bytes |
| Sniffing fallback | `magika` | ML-классификатор Google для спорных случаев |
| PDF baseline | `pymupdf4llm` | Быстро, локально, Markdown-готово, без ML |
| PDF tables/layout | `pdfplumber` | Тонкая работа с таблицами; основа для scout |
| PDF utility | `pypdf`, `pikepdf` | Metadata, encryption, repair |
| PDF heavy | `docling` (optional, через `DOC2KB_HEAVY=1`) | Layout-aware extraction, лучшие таблицы |
| PDF OCR (system) | `ocrmypdf` (через brew) + Tesseract | Добавление text layer к сканам |
| PDF VLM | `mlx-vlm` + Qwen2-VL / DeepSeek-OCR / olmOCR-2 | Топ-качество на M-series, опционально |
| DOCX | `mammoth` (Markdown) + `python-docx` (scout/metadata) | Чистый Markdown + structure inspection |
| DOCX encrypted | `msoffcrypto-tool` | Расшифровка Office-файлов с паролем |
| PPTX | `python-pptx` | Полный доступ к shapes/notes/tables |
| XLSX | `openpyxl` + `pandas` | Таблицы → CSV/Markdown |
| HTML | `trafilatura` + `markdownify` | Boilerplate-stripping |
| EPUB | `ebooklib` + tradition pipe | Главы → Markdown |
| RTF/ODT | `pandoc` (через subprocess; `brew install pandoc`) | Универсальный fallback |
| Image OCR | `rapidocr-onnxruntime` | Pure-Python, без brew-зависимостей |
| Encoding | `charset-normalizer` | Детекция и конверсия |
| Tokenization | `tiktoken` | Оценка стоимости |

### 6.2 Blueprint SKILL.md (полный)

См. секцию 4.2 выше; ключевые элементы:
- «Push» description с триггерными терминами.
- 4-фазный workflow (Bootstrap → Scout → Decide → Extract → Assemble).
- Явные правила: no summarization, ask user on edges, log errors.
- Inventory скриптов как контракт.

### 6.3 Blueprint выходного формата (минимальный пример)

```
kb/
├── manifest.json
├── INDEX.md
├── llms.txt
├── AGENTS.md           # инструкция, как читать kb/
├── docs/
│   ├── 001-transformer.md
│   ├── 002-bert.md
│   ├── 003-intro-lecture.md     # из PPTX
│   ├── 004-syllabus.md          # из DOCX
│   └── 005-old-textbook.md      # из OCR/VLM
├── assets/
│   └── (опционально, картинки)
└── _logs/
    ├── extraction.log
    └── errors.json
```

Каждый `docs/*.md` — отдельный документ с YAML-frontmatter (см. 3.4).

### 6.4 Top-5 ловушек

1. **Тихий fallback на пустой текст из image-only PDF.** Naive `pypdf` на скане вернёт пустую строку, и без проверки агент сохранит «пустой документ». **Решение:** в каждом extraction-скрипте обязательно проверять минимальную длину результата и помечать в warnings.
2. **Игнорирование speaker notes в PPTX.** Multi-extractor бенчмарки регулярно теряют notes, потому что многие конвертеры (`markitdown`, `unstructured`) их не включают. **Решение:** обязательно использовать `python-pptx` для PPTX или явно проверять, что выбранный конвертер вытаскивает `slide.notes_slide`.
3. **Один гигантский .md.** Соблазн «всё в один файл» убивает retrieval; контекст-rot реальный эффект. **Решение:** per-source файлы + манифест + INDEX.
4. **Безудержная установка тяжёлых зависимостей.** `docling` тянет ~1 GB; `marker-pdf` плюс модели — ещё столько же. Если skill ставит их на первом запуске — пользователь будет ждать 15 минут. **Решение:** tier-стратегия. По умолчанию — лёгкий stack (`pymupdf4llm`+`pdfplumber`+`mammoth`+`python-pptx`+`pandoc`). Heavy (docling/marker) только по флагу или когда лёгкий не справился.
5. **Бинарный ответ да/нет на encrypted/scanned.** Skill должен **спрашивать**, не угадывать. И — главное — батчить все вопросы в одно сообщение. Иначе агент будет 10 раз останавливаться по дороге.

Дополнительные подводные камни:
- **OCRmyPDF на Apple Silicon** требует системного Tesseract; без него ошибка.
- **MLX-VLM** требует Python 3.10+ и достаточно RAM (16 GB минимум для 2B-моделей; 32+ для 7B).
- **`unstructured`** в API/cloud-режиме отправляет данные наружу — выбирайте `unstructured` локальный режим или избегайте.

### 6.5 Свежие (2025–2026) события, которые меняют ландшафт

- **Agent Skills как open standard** (декабрь 2025): Anthropic выпустила, OpenAI Codex CLI, Cursor, Jules, Factory приняли. SKILL.md теперь портабельная единица между платформами.
- **AGENTS.md** под Linux Foundation / Agentic AI Foundation — устаканенный стандарт для repo-level guidance.
- **VLM-OCR революция на Apple Silicon**: DeepSeek-OCR (октябрь 2025) выдаёт ~32 страницы/сек на M4 Max с 8-bit MLX-квантизацией. olmOCR-2-7B (AllenAI, 2025) с MLX 4-bit лидирует на OmniDocBench. dots.ocr (RedNote, 3B) обгоняет Gemini 2.5 Pro на бенчах. Это значит: **OCR для skill-а можно делать локально на качестве, сравнимом с paid API**.
- **Docling v2** (2025): стал стандартом для production RAG, особенно после интеграций с LangChain/LlamaIndex.
- **Marker `--use_llm`** (2025): возможность подключать локальный/удалённый LLM для повышения точности на критичных документах.
- **Microsoft markitdown** (2025): дешёвый baseline, но не заменяет специализированные конвертеры; полезен для quick-mode.
- **llms.txt принят основными docs-движками** (Cloudflare, Fern, и др.); генерация `llms.txt` в kb/ — будущее-готовый ход.
- **DeepLearning.ai курс «Agent Skills with Anthropic»** (начало 2026) — формальная учебная программа.

### 6.6 Edge-cases, явно покрытые в blueprint

| Edge case | Покрытие |
|---|---|
| Scanned PDF | Scout детектит через char_threshold; user выбирает strategy (tesseract / mlx-vlm / claude-pagewise / skip) |
| Encrypted PDF | `pikepdf.PasswordError` → user даёт пароль или skip |
| Password-protected DOCX/XLSX | `msoffcrypto-tool` |
| Corrupt file | qpdf repair attempt; иначе лог + skip |
| Embedded images в DOCX | `python-docx` детектит; обработка через RapidOCR или VLM-caption |
| Speaker notes в PPTX | `python-pptx` всегда включает `notes_slide.text` |
| Tables в PDF | `docling` (TableFormer) или `pdfplumber` для критичных |
| Multi-column PDF | `pymupdf4llm` (layout analysis) или `docling` |
| Формулы в PDF | `nougat` или `marker` |
| Большой файл (>500 страниц) | User confirmation; обработка по частям |
| Очень широкая таблица | CSV/JSON fenced block вместо Markdown |
| Изображения только PNG/JPG | RapidOCR + опционально VLM-описание |
| RTF/ODT/прочее | `pandoc` fallback |
| Unknown MIME | python-magic + magika, при low confidence — skip с warning |
| Битая кодировка txt | `charset-normalizer`, конверсия в UTF-8 |
| Очень большой корпус | Estimated tokens в manifest + предупреждение пользователю |

## 7. Сравнение с существующими решениями

## 7. Сравнение с существующими решениями и gap analysis

### 7.1 Соседние инструменты

**Code-репозитории → промпт:**
- **`repomix`** (yamadashy) — packs repository into single AI-friendly XML/Markdown файл. Поддерживает `--compress` (удаление комментариев, whitespace), фильтры. Ориентирован на код, не на смешанные документы.
- **`gitingest`** — то же, но проще; для GitHub-репо.
- **`files-to-prompt`** (simonw) — минималистичный CLI, конкатенирует файлы с заголовками.
- **`code2prompt`** (mufeedvh) — CLI с шаблонами, source tree, token counting.
- **`your-source-to-prompt.html`** (Dicklesworthstone) — браузерный single-HTML инструмент.

Эти инструменты **не покрывают сложные форматы** (PDF/DOCX/PPTX), не делают OCR, не имеют scout-фазы, не отдают манифест. Они — однотрюковые пакеры для исходного кода.

**Document-extraction пайплайны:**
- **LlamaIndex local readers** (`llama_index.readers.file`) — обёртки над PyMuPDF, docx2txt, и т.п. Хорошо для прямой RAG-индексации, но без LLM-friendly Markdown-выхода и без scout-фазы.
- **LangChain document loaders** — аналогично.
- **`Kreuzberg`** (Python lib) — лёгкий universal text extractor (~71 MB), быстрый; в бенчмарке автора он быстрее docling, но качество ниже на сложных layout.
- **`PDFstract`**, `pdf-to-markdown` (web UI/CLI) — сравнительные тулы для benchmarking разных PDF-экстракторов на одном файле.
- **Open WebUI document processing** — встроенная в Open WebUI ingestion для self-hosted setup; не реюзабельный standalone.
- **Anthropic's pre-built `pdf` skill** — отличный пример minimal PDF skill (использует pypdf/pdfplumber/qpdf). Покрывает only PDF.
- **Anthropic's `docx`, `pptx`, `xlsx` skills** — те, что power Claude.ai document creation. Они про **генерацию** документов, а не про extraction в kb.

**SaaS, которых пользователь хочет избегать:**
- LlamaParse (paid API), Mistral Document AI (paid), AWS Textract, Azure Document Intelligence, Google Document AI, Reducto, Unstructured.io API.

### 7.2 Где gap

Никто из существующих не делает одновременно:
1. **Smart scout-фазу** с детекцией всех проблемных случаев и единой батч-запросом пользователю.
2. **Heterogeneous corpus** (не один формат, а смесь).
3. **Local-first** на macOS, без paid API.
4. **Output, специально оптимизированный под второй сессионный ingestion** (manifest + INDEX + per-source .md), а не под RAG-векторизацию или человеческое чтение.
5. **Tier-стратегию extraction** (дешёвое сначала, тяжёлое по необходимости).
6. **Двухсессионный паттерн** (extraction session ↔ working session) как явный design pattern.

**Это и есть ниша doc2kb.** Похожие на бумаге проекты типа `repomix` решают узкий слайс (code only), а document-extraction библиотеки (docling, marker) — это библиотеки, а не агентский workflow с user interaction.

### 7.3 Что можно заимствовать

- **От repomix:** `--compress` идея (но для документов — структурная очистка, не code minification); single-file fallback output (когда корпус мелкий — давать опцию собрать в один файл).
- **От gitingest:** простой CLI-фронт.
- **От LlamaIndex:** docling-интеграция как hot upgrade-path для тех, кто потом хочет RAG.
- **От Anthropic skills (`pdf`, `skill-creator`):** структура SKILL.md, frontmatter conventions, references/scripts/assets layout, тестирование через subagents.
- **От llmstxt.org:** генерация `llms.txt` как индекса.
- **От Marker:** опциональный `--use_llm` mode — но в нашем skill это будет «отправить page как image в текущую Claude-сессию для description» как fallback опция.

### 7.4 Композиция с другими skills

doc2kb должен **сотрудничать** со существующими Anthropic skills:
- Можно установить вместе с `anthropics/skills/pdf` — но в SKILL.md описании doc2kb явно сказать, что doc2kb используется для **корпуса**, а pdf skill — для одиночных операций над одним файлом. Это снижает риск конфликта triggers.
- Парный skill `doc2kb-reader` (опционально) — для второй сессии.
- Skill-marketplace: учитывать MIT license, чтобы можно было опубликовать.

## 8. Финальный план реализации и заключение

## 8. Финальный план реализации (actionable checklist)

### Этап 1: MVP (1–2 дня)
1. Создать каркас skill: `~/.claude/skills/doc2kb/` с `SKILL.md`, `scripts/`, `references/`, `assets/`.
2. Написать `bootstrap.sh` (см. 4.4) с легковесным stack: `pymupdf4llm`, `pdfplumber`, `pypdf`, `pikepdf`, `python-magic`, `python-docx`, `mammoth`, `python-pptx`, `openpyxl`, `trafilatura`, `markdownify`, `charset-normalizer`, `tiktoken`.
3. Написать `scout_corpus.py`: классификация по типам (через `python-magic`), для PDF — text/image_only/encrypted/mixed/corrupt, для DOCX/PPTX — richness-метрики; выдаёт `_scout.json`.
4. Написать минимальные extraction скрипты: `extract_pdf_pymupdf4llm.py`, `extract_docx.py` (mammoth), `extract_pptx.py` (python-pptx с notes), `extract_md_txt.py` (с charset-normalizer и нормализацией).
5. Написать `normalize_md.py`: дедупликация header/footer, whitespace cleanup, удаление известного boilerplate.
6. Написать `build_manifest.py`: собирает `manifest.json`, `INDEX.md`, `llms.txt`, `AGENTS.md`.
7. Написать SKILL.md с правильной push-description, workflow phases, scripts inventory.

### Этап 2: Heavy + edge cases (2–3 дня)
8. Добавить опциональные heavy dependencies в bootstrap (`DOC2KB_HEAVY=1` → `docling`, `marker-pdf`).
9. Добавить `extract_pdf_docling.py`, `extract_pdf_marker.py` для сложных layout/таблиц.
10. Интегрировать OCR-маршрут: `extract_pdf_ocr.py` через OCRmyPDF (системная зависимость) → затем pymupdf4llm.
11. Добавить pandoc fallback для odt/rtf/epub.
12. Добавить RapidOCR для PNG/JPG.
13. Расширить scout для batch-запроса decisions у пользователя; добавить раздел в SKILL.md «How to ask the user».

### Этап 3: VLM-маршрут (опционально, 1–2 дня)
14. Добавить `DOC2KB_VLM=1` → `mlx-vlm` + загрузка Qwen2-VL/olmOCR-2/DeepSeek-OCR (MLX-квантизация).
15. Скрипт `extract_with_vlm.py` для page-by-page VLM-extraction.
16. Документация в `references/vlm-models.md`: какие модели выбрать (size vs quality), как переключаться.

### Этап 4: Polish (1 день)
17. Testing на разнообразном корпусе (см. 4.4).
18. Написать `references/format-spec.md` (полная спецификация формата вывода).
19. Написать `references/pitfalls.md` (со всеми «не делать» из секции 5.3).
20. Написать `references/extraction-recipes.md` (для каждого варианта `extraction_strategy` — какой скрипт вызвать).
21. Опубликовать как Claude Code plugin / на agentskills.io / в личном Git.

### Критерии готовности

- [ ] Skill активируется на корректные триггеры в Claude Code (тест: "обработай папку ~/Documents/research").
- [ ] Скаут корректно классифицирует PDF на text/image_only/encrypted.
- [ ] Encrypted и scanned PDF вызывают user prompt, не silent skip.
- [ ] PPTX speaker notes присутствуют в выходном .md.
- [ ] Embedded images в DOCX отмечены в frontmatter (даже если не извлекаются).
- [ ] `manifest.json` корректно отражает количество файлов и токенов.
- [ ] `INDEX.md` читаем агентом и даёт навигацию по корпусу.
- [ ] Во второй Claude-сессии открытие kb/ → агент сам читает CLAUDE.md/AGENTS.md → корректно отвечает на вопросы о содержимом корпуса.
- [ ] Token count в манифесте ±15% от реального.
- [ ] Лёгкая установка (без heavy deps) работает на чистой macOS.

## Заключение

Skill, который вы хотите построить, занимает реальную нишу: пересечение **agentic workflow patterns** (двухсессионная extraction/working модель, progressive disclosure), **современных локальных document-extraction технологий** (pymupdf4llm / docling / marker / MLX-VLM на Apple Silicon) и **LLM-оптимизированных output форматов** (Markdown + JSON manifest + llms.txt). Готового аналога нет — `repomix`/`gitingest` это про код, `docling`/`marker` это библиотеки без user-interaction слоя, Anthropic'овский `pdf` skill это про одиночные операции.

Главные дизайн-решения, которые я бы порекомендовал зафиксировать заранее: **(1)** tier-стратегия extraction (lightweight по умолчанию, heavy/VLM по флагу), **(2)** скаут возвращает структурированный JSON и батчит решения пользователя в один вопрос, **(3)** per-source Markdown файлы с YAML-frontmatter плюс манифест/INDEX, **(4)** verbatim preservation вместо суммаризации, со структурной очисткой, **(5)** двухсессионный workflow явно описан в SKILL.md, а на стороне kb/ лежит короткий `AGENTS.md`/`CLAUDE.md` с инструкцией для второй сессии. Этого достаточно, чтобы skill был и полезен для повседневной работы, и устойчив на сложных корпусах с зашифрованными, сканированными и битыми файлами.

Отчёт собран из 8 секций (см. выше): резюме/итоговое решение, состояние локальных библиотек извлечения 2024–2026, scout-скрипты и детекция, оптимальный формат вывода для LLM, архитектура skill и best practices Claude Code, сжатие и информационная плотность, конкретные рекомендации и blueprint, сравнение с существующими решениями, финальный план реализации и заключение.

Ключевые тезисы отчёта:

1. **Tech stack (macOS, local-first):** базовый слой — `pymupdf4llm` для native PDF, `pdfplumber` для таблиц/scout, `pikepdf` для encrypted, `mammoth`+`python-docx` для DOCX, `python-pptx` для PPTX (с обязательным извлечением speaker notes), `pandoc`/`trafilatura`/`ebooklib` для прочих форматов, `python-magic`+`magika` для sniffing. Heavy tier (опционально): `docling` (IBM, лучший out-of-the-box для RAG) или `marker-pdf` (Surya OCR, MPS support). VLM-tier на Apple Silicon: `mlx-vlm` + DeepSeek-OCR / olmOCR-2-7B / Qwen2-VL / dots.ocr.

2. **Архитектура skill:** канонический Anthropic layout (SKILL.md + scripts/ + references/ + assets/) с push-description; 4-фазный workflow Bootstrap → Scout → Decide → Extract → Assemble; venv внутри skill с tier-стратегией установки (lightweight по умолчанию, `DOC2KB_HEAVY=1` и `DOC2KB_VLM=1` для тяжёлого).

3. **Scout-фаза:** классификация PDF по порогу символов на страницу (text/image_only/mixed/encrypted/corrupt), детекция encryption через `pikepdf.PasswordError`, richness-метрики для DOCX/PPTX (embedded images, speaker notes, tables, equations), сниффинг через libmagic + magika fallback, оценка токенов через tiktoken. Все решения, требующие пользователя, батчатся в одно сообщение.

4. **Формат вывода:** Markdown как носитель содержания + JSON для манифеста. Иерархия: `kb/manifest.json` + `kb/INDEX.md` + `kb/docs/<slug>.md` + опционально `kb/llms.txt` и `kb/AGENTS.md`. Каждый .md имеет YAML-frontmatter с source/sha256/extraction_method/tokens. Page anchors `[page N]`. Per-source файлы вместо одной простыни (избежание context rot).

5. **Двухсессионная модель:** extraction session запускает skill, working session открывается с kb/ и читает CLAUDE.md/AGENTS.md → INDEX.md → manifest.json → docs/* по требованию. Опционально парный `doc2kb-reader` skill.

6. **Сжатие:** дедупликация header/footer, удаление boilerplate/whitespace/control chars, VLM-caption для картинок вместо хранения пикселей, CSV для широких таблиц. **Категорически не суммаризировать** — пользователь хочет verbatim equivalence.

7. **Top-5 ловушек:** тихий fallback на пустой текст из сканов; игнорирование PPTX speaker notes; один гигантский файл; безудержная установка heavy deps; угадывание решений вместо запроса пользователя.

8. **Gap:** ни `repomix`/`gitingest`/`files-to-prompt` (только код), ни `docling`/`marker` (библиотеки без агентского слоя), ни Anthropic'овский pre-built `pdf` skill (только один формат, без scout/manifest) не покрывают одновременно heterogeneous corpus + smart scout + local-first + двухсессионный output. Это и есть ниша doc2kb.

9. **Свежие (2025–2026) события:** Agent Skills как open standard принят OpenAI/Cursor/Jules; AGENTS.md под Linux Foundation; VLM-OCR революция на Apple Silicon (DeepSeek-OCR ~32 pages/sec на M4 Max); docling v2 стал стандартом для production RAG; llms.txt принят Anthropic/OpenAI/Cloudflare.

Отчёт содержит конкретные code-сниппеты для каждого скрипта-скаута, полный пример SKILL.md frontmatter и body, blueprint выходного формата с примерами `manifest.json`, `INDEX.md`, отдельного `.md` с frontmatter, а также 4-этапный actionable checklist реализации (MVP за 1–2 дня → heavy/edge cases → VLM → polish) с критериями готовности.