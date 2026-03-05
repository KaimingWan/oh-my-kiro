#!/usr/bin/env python3
"""为 lessons-learned.md 中的教训生成触发场景文件，索引到 OV。

通用 OMCC 框架脚本 — 自动检测项目根目录下的 knowledge/lessons-learned.md。

Usage:
  python3 scripts/generate-lesson-scenarios.py --dry-run
  python3 scripts/generate-lesson-scenarios.py
  python3 scripts/generate-lesson-scenarios.py --single '<text>'
  python3 scripts/generate-lesson-scenarios.py --index-only
"""
import argparse
import json
import os
import re
import socket
import sys
from pathlib import Path

# OMCC_PROJECT_DIR is set by hooks; fallback: two levels up from this script's .omcc location
PROJECT_DIR = Path(os.environ.get("OMCC_PROJECT_DIR", Path(__file__).resolve().parent.parent.parent))
LESSONS_FILE = PROJECT_DIR / "knowledge" / "lessons-learned.md"
SCENARIOS_DIR = PROJECT_DIR / "knowledge" / "lesson-scenarios"
OV_SOCKET = os.environ.get("OV_SOCKET", "/tmp/omcc-ov.sock")


def slugify(text: str) -> str:
    s = re.sub(r'[^\w\u4e00-\u9fff]+', '-', text[:60]).strip('-').lower()
    return s or 'lesson'


def parse_table_lessons(content: str) -> list[dict]:
    lessons = []
    pat = re.compile(
        r'^\|\s*(\d{4}-\d{2}-\d{2})\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|',
        re.MULTILINE,
    )
    for m in pat.finditer(content):
        date, scene, error, root_cause, fix = m.groups()
        if date.startswith('日期') or date.startswith('---'):
            continue
        lessons.append({
            'type': 'table', 'date': date.strip(),
            'scene': scene.strip(), 'error': error.strip(),
            'root_cause': root_cause.strip(), 'fix': fix.strip(),
            'title': f"{scene.strip()}: {error.strip()}"[:80],
        })
    return lessons


def parse_section_lessons(content: str) -> list[dict]:
    lessons = []
    pat = re.compile(r'^## (\d{4}-\d{2}-\d{2}): (.+?)$', re.MULTILINE)
    matches = list(pat.finditer(content))
    for i, m in enumerate(matches):
        date, title = m.group(1), m.group(2).strip()
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
        body = content[start:end].strip()
        if '成功案例' in title or '规则沉淀' in title:
            continue
        lessons.append({'type': 'section', 'date': date, 'title': title, 'body': body})
    return lessons


def format_lesson(lesson: dict) -> str:
    if lesson['type'] == 'table':
        return (f"场景: {lesson['scene']}\n错误: {lesson['error']}\n"
                f"根因: {lesson['root_cause']}\n修复: {lesson['fix']}")
    return f"标题: {lesson['title']}\n{lesson['body']}"


def scenarios_dry(lesson: dict) -> list[str]:
    title = lesson.get('title', '')
    scene = lesson.get('scene', '')
    error = lesson.get('error', '')
    out = [f"用户遇到类似问题: {title}"]
    if scene:
        out.append(f"用户正在操作: {scene}")
    if error:
        out.append(f"用户可能犯同样的错: {error}")
    if not scene and not error:
        out.append(f"用户询问相关话题: {title}")
        out.append(f"用户需要避免: {title} 中的错误")
    return out[:5]


def scenarios_llm(lesson: dict) -> list[str]:
    try:
        from openai import AzureOpenAI
    except ImportError:
        return scenarios_dry(lesson)
    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
    key = os.environ.get("AZURE_OPENAI_API_KEY")
    if not endpoint or not key:
        return scenarios_dry(lesson)
    client = AzureOpenAI(
        azure_endpoint=endpoint, api_key=key,
        api_version=os.environ.get("AZURE_OPENAI_API_VERSION", "2024-12-01-preview"),
    )
    try:
        resp = client.chat.completions.create(
            model=os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-4o"),
            messages=[
                {"role": "system", "content": "你是一个场景生成器。给定一条经验教训，生成 3-5 个用户可能说的话（触发场景），让系统能召回这条教训。只输出 JSON 数组。"},
                {"role": "user", "content": format_lesson(lesson)},
            ],
            temperature=0.7, max_tokens=500,
        )
        return json.loads(resp.choices[0].message.content)
    except Exception as e:
        print(f"⚠️ LLM call failed ({e}), falling back to dry-run", file=sys.stderr)
        return scenarios_dry(lesson)


def write_scenario(lesson: dict, scenarios: list[str]) -> Path:
    SCENARIOS_DIR.mkdir(parents=True, exist_ok=True)
    date = lesson.get('date', '')
    slug = slugify(lesson.get('title', lesson.get('scene', 'unknown')))
    path = SCENARIOS_DIR / f"lesson-scenario-{f'{date}-' if date else ''}{slug}.md"
    lines = "\n".join(f"- {s}" for s in scenarios)
    path.write_text(
        f"# Lesson: {lesson.get('title', 'Unknown')}\n\n"
        f"## 触发场景\n{lines}\n\n"
        f"## 教训内容\n{format_lesson(lesson)}\n",
        encoding='utf-8',
    )
    return path


def ov_add(filepath: Path) -> bool:
    if not Path(OV_SOCKET).exists():
        return False
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(30)
        s.connect(OV_SOCKET)
        s.sendall(json.dumps({'cmd': 'add_resource', 'path': str(filepath), 'reason': 'lesson-scenario'}).encode())
        resp = json.loads(s.recv(65536).decode())
        s.close()
        return resp.get('ok', False)
    except Exception:
        return False


def main():
    ap = argparse.ArgumentParser(description='Generate lesson trigger scenarios')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--single', type=str)
    ap.add_argument('--index-only', action='store_true')
    args = ap.parse_args()

    if args.index_only:
        files = sorted(SCENARIOS_DIR.glob('lesson-scenario-*.md'))
        ok = sum(1 for f in files if ov_add(f))
        print(f"{ok}/{len(files)} indexed to OV")
        return

    if args.single:
        lesson = {'type': 'section', 'date': '', 'title': args.single[:80], 'body': args.single}
        scns = scenarios_dry(lesson) if args.dry_run else scenarios_llm(lesson)
        path = write_scenario(lesson, scns)
        print(f"✓ scenario file: {path.name}")
        if not args.dry_run:
            print(f"  {'✓' if ov_add(path) else '✗'} OV indexed")
        print("1 scenarios generated")
        return

    if not LESSONS_FILE.exists():
        print(f"❌ {LESSONS_FILE} not found", file=sys.stderr)
        sys.exit(1)

    content = LESSONS_FILE.read_text(encoding='utf-8')
    all_lessons = parse_table_lessons(content) + parse_section_lessons(content)
    if not all_lessons:
        print("❌ No lessons found", file=sys.stderr)
        sys.exit(1)

    print(f"📋 Found {len(all_lessons)} lessons")
    gen = scenarios_dry if args.dry_run else scenarios_llm
    for lesson in all_lessons:
        scns = gen(lesson)
        path = write_scenario(lesson, scns)
        print(f"✓ {path.name} ({len(scns)} scenarios)")
        if not args.dry_run:
            ov_add(path)
    print(f"{len(all_lessons)} scenarios generated")


if __name__ == '__main__':
    main()
