---
name: omk-pdf-gen
description: >
  Generate professional PDF documents with correct CJK (Chinese/Japanese/Korean) rendering.
  Trigger when user says 'generate PDF', 'create PDF', 'export PDF', '生成 PDF', '导出 PDF',
  '做个 PDF', 'make a PDF', or when any task requires producing a PDF file.
  Also trigger when user mentions PDF formatting issues, garbled text, or font problems.
---

# PDF Generation Skill

## Trigger Examples
- "帮我生成一个报价 PDF"
- "把这个内容导出成 PDF"
- "PDF 中文乱码怎么办"
- "generate a comparison PDF for this customer"
- "create a budget proposal PDF"

## Approach: HTML + weasyprint

Use **HTML + CSS → weasyprint** pipeline. Do NOT use reportlab for documents containing CJK text.

Why:
- reportlab CID fonts (STSong-Light) have incomplete glyph coverage — symbols like `•` render as garbage (e.g. "煉")
- reportlab cannot read macOS SIP-protected TTC fonts (PingFang etc.)
- reportlab `canvas` API requires manual coordinate positioning — fragile and ugly
- weasyprint uses system fontconfig — correct font resolution out of the box

## Workflow

### Step 1: Write HTML string in Python

```python
HTML = """\
<!DOCTYPE html>
<html lang="zh">
<head><meta charset="utf-8">
<style>
@page { size: A4; margin: 2cm 2.2cm; }
body { font-family: "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC", sans-serif; ... }
</style></head>
<body>...</body></html>
"""
```

### Step 2: Write to temp HTML, convert, clean up

```python
import subprocess, os
html_tmp = output_path.replace('.pdf', '.html')
with open(html_tmp, 'w', encoding='utf-8') as f:
    f.write(HTML)
subprocess.run(['weasyprint', html_tmp, output_path], check=True)
os.remove(html_tmp)
```

## Font Rules (Critical)

| Platform | CSS font-family | Notes |
|----------|----------------|-------|
| macOS | `"Hiragino Sans GB", "Heiti SC"` | Verified via `fc-list :lang=zh` |
| Linux | `"Noto Sans CJK SC", "WenQuanYi Micro Hei"` | Install `fonts-noto-cjk` if missing |
| Fallback | `sans-serif` | Always include as last resort |

**Never use these in weasyprint CSS:**
- `-apple-system` — weasyprint doesn't understand Apple system font aliases
- `"PingFang SC"` — fontconfig often can't resolve it even though macOS has it
- `"STSong-Light"` — CID font name, not a real font family for CSS

**Before generating**, verify CJK fonts are available:
```bash
fc-list :lang=zh family | head -10
```

## Styling Best Practices

Use standard HTML elements — weasyprint handles them well:

- `<table>` with CSS `border-collapse: collapse` for data tables
- `<ul>/<li>` for bullet lists (no manual bullet symbols needed)
- `<h1>-<h3>` for headings
- `<hr>` for dividers
- CSS `@page` for margins and page size

### Recommended CSS skeleton

```css
@page { size: A4; margin: 2cm 2.2cm; }
body { font-family: "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC", sans-serif;
       font-size: 11pt; color: #1a1a2e; line-height: 1.7; }
h1 { font-size: 22pt; text-align: center; }
h3 { font-size: 13pt; color: #1a73e8; }
table { width: 100%; border-collapse: collapse; font-size: 10pt; }
th { background: #1a1a2e; color: #fff; padding: 7pt 10pt; text-align: left; }
td { padding: 6pt 10pt; border-bottom: 1px solid #e5e7eb; }
tr:nth-child(even) td { background: #f8f9fa; }
```

## When reportlab IS acceptable

English-only documents where you need precise programmatic layout (charts, diagrams, pixel-perfect positioning). Use `platypus` (SimpleDocTemplate + Paragraph + Table), never raw `canvas` API.

Reference: `tools/gen-73strings-pdfs.py` — good example of reportlab platypus for English PDFs.

## Anti-Patterns (from real incidents)

| Don't | Why | Do Instead |
|-------|-----|-----------|
| reportlab + STSong-Light for CJK | `•` → "煉", incomplete glyphs | weasyprint + system fonts |
| reportlab `canvas` manual positioning | Fragile coordinates, misaligned text | weasyprint or reportlab `platypus` |
| CSS `font-family: -apple-system` | weasyprint can't resolve it | Use `"Hiragino Sans GB"` |
| CSS `font-family: "PingFang SC"` | fontconfig often fails to find it | Use `"Hiragino Sans GB"` |
| Helvetica-Bold for table headers with CJK | CJK chars render as ■■■ | Use CJK font + `font-weight: bold` |
| Hardcode font without checking | Fails on different OS | Run `fc-list :lang=zh` first |

## Output

Place generated script in `tools/gen-<name>-pdf.py`. The script should:
1. Define HTML as a string constant
2. Write temp HTML → call weasyprint → remove temp HTML
3. Print the output path on success
