#!/usr/bin/env python3
"""Validate the static flutterm product site."""

from __future__ import annotations

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse


SITE_ROOT = Path(__file__).resolve().parents[1]
PAGES = [
    Path("index.html"),
    Path("features/index.html"),
    Path("technology/index.html"),
    Path("roadmap/index.html"),
    Path("open-source/index.html"),
]
REQUIRED_ASSETS = [
    Path("assets/styles.css"),
    Path("assets/app.js"),
]
FORBIDDEN_COPY = [
    "立即下载",
    "全平台已经可用",
    "完全兼容",
    "官网",
    "内部任务编号",
    "内部验证日志",
    "首页负责",
    "路线图用用户能读懂",
    "技术证明要",
]
REQUIRED_APP_SNIPPETS = [
    "flutterm-site-theme",
    'dataset.theme = "system"',
    "prefers-reduced-motion",
]
REQUIRED_CSS_SNIPPETS = [
    "prefers-reduced-motion",
    "data-theme=\"dark\"",
    "data-theme=\"light\"",
    "--on-accent",
    "color: var(--on-accent)",
    ".terminal-hero",
]


class LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str]] = []
        self.scripts: list[str] = []
        self.stylesheets: list[str] = []
        self.buttons: list[dict[str, str]] = []

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        values = {key: value or "" for key, value in attrs}
        if tag == "a" and "href" in values:
            self.links.append((values["href"], values.get("class", "")))
        if tag == "script" and "src" in values:
            self.scripts.append(values["src"])
        if tag == "link" and values.get("rel") == "stylesheet":
            self.stylesheets.append(values.get("href", ""))
        if tag == "button":
            self.buttons.append(values)


def fail(message: str) -> None:
    raise SystemExit(f"site validation failed: {message}")


def read_text(relative_path: Path) -> str:
    path = SITE_ROOT / relative_path
    if not path.exists():
        fail(f"missing {relative_path}")
    return path.read_text(encoding="utf-8")


def resolve_local_reference(source: Path, href: str) -> Path | None:
    parsed = urlparse(href)
    if parsed.scheme or parsed.netloc or href.startswith("#"):
        return None
    clean_href = href.split("#", 1)[0].split("?", 1)[0]
    if not clean_href:
        return None
    resolved = (SITE_ROOT / source.parent / clean_href).resolve()
    site_root = SITE_ROOT.resolve()
    if site_root not in resolved.parents and resolved != site_root:
        fail(f"{source} links outside site root: {href}")
    if clean_href.endswith("/") or resolved.is_dir():
        resolved = resolved / "index.html"
    return resolved


def validate_page(relative_path: Path) -> None:
    html = read_text(relative_path)
    parser = LinkParser()
    parser.feed(html)

    for copy in FORBIDDEN_COPY:
        if copy in html:
            fail(f"{relative_path} contains forbidden copy: {copy}")

    if 'id="main-content"' not in html:
        fail(f"{relative_path} is missing main-content landmark")
    if "theme-toggle" not in html:
        fail(f"{relative_path} is missing theme toggle")
    if "assets/styles.css" not in html and "../assets/styles.css" not in html:
        fail(f"{relative_path} is missing shared stylesheet")
    if "assets/app.js" not in html and "../assets/app.js" not in html:
        fail(f"{relative_path} is missing shared script")

    theme_buttons = [
        button for button in parser.buttons if button.get("data-theme-toggle") == ""
    ]
    if len(theme_buttons) != 1:
        fail(f"{relative_path} must have exactly one data-theme-toggle button")

    for href, _class_name in parser.links:
        target = resolve_local_reference(relative_path, href)
        if target is not None and not target.exists():
            fail(f"{relative_path} has broken link {href}")


def validate_assets() -> None:
    for asset in REQUIRED_ASSETS:
        if not (SITE_ROOT / asset).exists():
            fail(f"missing {asset}")

    app_js = read_text(Path("assets/app.js"))
    for snippet in REQUIRED_APP_SNIPPETS:
        if snippet not in app_js:
            fail(f"assets/app.js missing required snippet: {snippet}")

    styles = read_text(Path("assets/styles.css"))
    for snippet in REQUIRED_CSS_SNIPPETS:
        if snippet not in styles:
            fail(f"assets/styles.css missing required snippet: {snippet}")


def main() -> None:
    for page in PAGES:
        validate_page(page)
    validate_assets()
    print("site validation passed")


if __name__ == "__main__":
    main()
