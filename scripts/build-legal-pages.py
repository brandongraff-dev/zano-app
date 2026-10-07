#!/usr/bin/env python3
"""Build landing/privacy.html and landing/terms.html from docs/launch/*.md (session 33).

The app links to https://zano.app/privacy and /terms (SettingsCopy.swift, PaywallView.swift), and
App Review opens both. The source of truth stays the Markdown the lawyer reviews; this script turns
it into pages that match the landing site.

    python3 scripts/build-legal-pages.py           # writes landing/privacy.html + landing/terms.html
    python3 scripts/build-legal-pages.py --draft   # preview with placeholders, into build/legal-draft/

Without --draft it refuses (exit 1) while any `[PLACEHOLDER]`-style marker is left, so a draft can
never be published by accident. Internal notes (lines starting with `>`) are always dropped: they
are written for the founder and the lawyer, not for users.

No dependencies: the Markdown in docs/launch uses headings, paragraphs, bullet and numbered lists,
tables, bold/italic, inline code, links and rules; that subset is converted here.
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGES = [
    ("docs/launch/privacy-policy.md", "privacy.html", "Privacy Policy"),
    ("docs/launch/terms-of-use.md", "terms.html", "Terms of Use"),
]
# `[COMPANY LEGAL NAME]`, `[N]`, `[CONFIRM per provider]`, `[CONFIRM WHEN X IS LIVE: [N] days]` (one level of
# nesting, and it may wrap across lines): a bracket opening with a
# capital word. Markdown links (`[text](url)`) are not markers.
PLACEHOLDER = re.compile(r"\[[A-Z][A-Z0-9_/-]*(?:[ :][^\]\[]*(?:\[[^\]]*\][^\]\[]*)*)?\](?!\()")


def inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![*\w])\*([^*]+)\*(?!\w)", r"<em>\1</em>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"(?<![\"=>])\b(https?://[^\s<)]+)", r'<a href="\1">\1</a>', out)
    return out


def convert(md: str) -> tuple[str, str]:
    """Returns (title, body html). The first `# ` heading is the title."""
    lines = [l for l in md.splitlines() if not l.lstrip().startswith(">")]
    title, body, para, i = "", [], [], 0

    def flush() -> None:
        if para:
            # A line opening with bold ("**Effective date:**") after another line starts a new line.
            text = " ".join(para)
            text = re.sub(r" (?=\*\*[^*]+:\*\*)", "\n", text)
            body.append("<p>" + "<br />".join(inline(t) for t in text.split("\n")) + "</p>")
            para.clear()

    while i < len(lines):
        line = lines[i].rstrip()
        if not line.strip():
            flush(); i += 1; continue
        if m := re.match(r"^(#{1,4})\s+(.*)", line):
            flush()
            level = len(m.group(1))
            if level == 1 and not title:
                title = m.group(2).strip()
            else:
                slug = re.sub(r"[^a-z0-9]+", "-", m.group(2).lower()).strip("-")
                body.append(f'<h{level} id="{slug}">{inline(m.group(2))}</h{level}>')
            i += 1; continue
        if re.match(r"^-{3,}$|^\*{3,}$", line.strip()):
            flush(); body.append("<hr />"); i += 1; continue
        if line.lstrip().startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")]); i += 1
            head, rest = rows[0], [r for r in rows[1:] if not all(re.fullmatch(r":?-+:?", c) for c in r)]
            t = ["<div class=\"legal__table\"><table><thead><tr>"]
            t += [f"<th>{inline(c)}</th>" for c in head]
            t.append("</tr></thead><tbody>")
            for r in rest:
                t.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
            t.append("</tbody></table></div>")
            body.append("".join(t)); continue
        if m := re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)", line):
            flush()
            tag = "ol" if m.group(2)[0].isdigit() else "ul"
            items: list[str] = []
            while i < len(lines):
                lm = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)", lines[i])
                if lm:
                    items.append(lm.group(3).strip())
                elif lines[i].strip() and lines[i].startswith(" ") and items:
                    items[-1] += " " + lines[i].strip()  # wrapped or nested continuation
                else:
                    break
                i += 1
            body.append(f"<{tag}>" + "".join(f"<li>{inline(x)}</li>" for x in items) + f"</{tag}>")
            continue
        para.append(line.strip()); i += 1
    flush()
    return title, "\n".join(body)


def page(title: str, body: str, draft: bool) -> str:
    banner = (
        '<p class="legal__draft">Draft preview: placeholders are not filled in. Do not publish.</p>'
        if draft else ""
    )
    robots = '<meta name="robots" content="noindex" />' if draft else ""
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{html.escape(title)} · ZANO</title>
  {robots}
  <link rel="icon" href="assets/buddies/stash-happy.webp" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@500;600;700;800&display=swap" rel="stylesheet" />
  <link rel="stylesheet" href="style.css" />
</head>
<body>
  <header class="nav glass">
    <div class="wrap nav__in">
      <a href="./" class="logo">zan<i>o</i></a>
      <a href="support.html" class="btn btn--sm">Support</a>
    </div>
  </header>
  <main class="legal wrap">
    {banner}
    <h1>{html.escape(title)}</h1>
{body}
  </main>
  <footer class="footer">
    <div class="wrap"><span>&copy; ZANO</span><span><a href="privacy.html">Privacy</a> · <a href="terms.html">Terms</a> · <a href="support.html">Support</a></span></div>
  </footer>
</body>
</html>
"""


def main() -> int:
    draft = "--draft" in sys.argv
    out_dir = ROOT / ("build/legal-draft" if draft else "landing")
    out_dir.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    built: list[tuple[Path, str]] = []
    for src, name, fallback_title in PAGES:
        md = (ROOT / src).read_text(encoding="utf-8")
        title, body = convert(md)
        published = "\n".join(l for l in md.splitlines() if not l.lstrip().startswith(">"))
        for m in PLACEHOLDER.finditer(published):
            line = md.splitlines().index(published.splitlines()[published.count("\n", 0, m.start())]) + 1
            problems.append(f"{src}:{line}: {' '.join(m.group(0).split())[:70]}")
        built.append((out_dir / name, page(title.replace("ZANO ", "") or fallback_title, body, draft)))
    if problems and not draft:
        print("Not publishing: placeholders are still in the legal text.\n", file=sys.stderr)
        print("\n".join(problems), file=sys.stderr)
        print(f"\n{len(problems)} marker(s). Fill them in (or delete sentences for services that are off),"
              " then run again. Use --draft to preview.", file=sys.stderr)
        return 1
    for path, text in built:
        path.write_text(text, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)}")
    if draft:
        (out_dir / "style.css").write_text((ROOT / "landing/style.css").read_text(encoding="utf-8"), encoding="utf-8")
        print(f"{len(problems)} placeholder(s) remain; draft pages are not for publishing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
