#!/usr/bin/env python3
"""Render deterministic Chinese text diagrams for the static site."""

from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIRS = {
    "frame": ROOT / "assets" / "images" / "frame-diff",
    "feature": ROOT / "assets" / "images" / "feature-visuals",
}
WIDTH = 1536
HEIGHT = 1024

FONT_PATH = Path("/System/Library/Fonts/STHeiti Medium.ttc")
LIGHT_FONT_PATH = Path("/System/Library/Fonts/STHeiti Light.ttc")

NAVY = "#0d1b2f"
MUTED = "#334155"
GREEN = "#16803a"
TEAL = "#00838a"
BLUE = "#1559bd"
ORANGE = "#d97706"
PURPLE = "#5b50a6"
LINE = "#9db6c5"
PALE = "#f8fbfd"
PALE_GREEN = "#edf8f1"
PALE_BLUE = "#edf5ff"
PALE_ORANGE = "#fff7ed"
WHITE = "#ffffff"
INK = "#111827"


def font(size: int, light: bool = False) -> ImageFont.FreeTypeFont:
    path = LIGHT_FONT_PATH if light and LIGHT_FONT_PATH.exists() else FONT_PATH
    return ImageFont.truetype(str(path), size)


F_TITLE = font(58)
F_SUBTITLE = font(29, light=True)
F_H2 = font(28)
F_H3 = font(22)
F_BODY = font(20, light=True)
F_SMALL = font(17, light=True)
F_MONO = font(18, light=True)


def text_size(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont) -> tuple[int, int]:
    if not text:
        return 0, 0
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1]


def wrap_text(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    no_break_before = set("，。；：？！、,.!?;:)）]")
    lines: list[str] = []
    for paragraph in text.split("\n"):
        current = ""
        tokens = re.findall(r"[A-Za-z0-9_./()+#:-]+|\s+|.", paragraph)
        for token in tokens:
            candidate = current + token
            if current and text_size(draw, candidate, fnt)[0] > max_width:
                if token in no_break_before:
                    current = candidate
                else:
                    lines.append(current.rstrip())
                    current = token.lstrip()
            else:
                current = candidate
        if current:
            lines.append(current.rstrip())
    return lines or [""]


def draw_wrapped(
    draw: ImageDraw.ImageDraw,
    text: str,
    xy: tuple[int, int],
    max_width: int,
    fnt: ImageFont.FreeTypeFont,
    fill: str = INK,
    line_gap: int = 8,
) -> int:
    x, y = xy
    for line in wrap_text(draw, text, fnt, max_width):
        draw.text((x, y), line, font=fnt, fill=fill)
        y += text_size(draw, line, fnt)[1] + line_gap
    return y


def rounded(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill: str, outline: str = LINE, width: int = 2, radius: int = 14) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def arrow(draw: ImageDraw.ImageDraw, start: tuple[int, int], end: tuple[int, int], color: str = "#274254", width: int = 5) -> None:
    draw.line((start, end), fill=color, width=width)
    x1, y1 = start
    x2, y2 = end
    if abs(x2 - x1) >= abs(y2 - y1):
        sign = 1 if x2 > x1 else -1
        pts = [(x2, y2), (x2 - sign * 18, y2 - 11), (x2 - sign * 18, y2 + 11)]
    else:
        sign = 1 if y2 > y1 else -1
        pts = [(x2, y2), (x2 - 11, y2 - sign * 18), (x2 + 11, y2 - sign * 18)]
    draw.polygon(pts, fill=color)


def mini_grid(draw: ImageDraw.ImageDraw, x: int, y: int, cols: int = 10, rows: int = 8, cell: int = 16, highlights: tuple[int, ...] = (2, 5), color: str = "#27b7ad") -> None:
    w = cols * cell
    h = rows * cell
    rounded(draw, (x - 8, y - 8, x + w + 8, y + h + 8), "#1f2933", "#0f1720", 3, 10)
    for r in range(rows):
        for c in range(cols):
            fill = color if r in highlights and 2 <= c <= 7 else "#3a3f45"
            draw.rectangle((x + c * cell, y + r * cell, x + (c + 1) * cell - 2, y + (r + 1) * cell - 2), fill=fill, outline="#111827")


def terminal_box(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, lines: list[str]) -> None:
    rounded(draw, (x, y, x + w, y + 120), "#111827", "#1f2937", 2, 10)
    ty = y + 18
    for line in lines[:4]:
        draw.text((x + 18, ty), line, font=F_MONO, fill="#e5fdf7")
        ty += 24


def card(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str, body: str, accent: str = TEAL, fill: str = WHITE) -> None:
    x1, y1, x2, y2 = box
    rounded(draw, box, fill, accent, 2, 13)
    draw.rectangle((x1, y1, x2, y1 + 44), fill=accent)
    draw.rounded_rectangle((x1, y1, x2, y1 + 60), radius=13, fill=accent)
    draw.rectangle((x1, y1 + 44, x2, y1 + 60), fill=fill)
    draw.text((x1 + 18, y1 + 10), title, font=F_H3, fill=WHITE)
    draw_wrapped(draw, body, (x1 + 18, y1 + 66), x2 - x1 - 36, F_BODY, MUTED, 8)


def panel(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str, items: list[str], accent: str, fill: str = WHITE) -> None:
    x1, y1, x2, y2 = box
    rounded(draw, box, fill, accent, 3, 15)
    draw.rectangle((x1, y1, x2, y1 + 52), fill=accent)
    draw.rounded_rectangle((x1, y1, x2, y1 + 68), radius=15, fill=accent)
    draw.rectangle((x1, y1 + 52, x2, y1 + 68), fill=fill)
    draw.text((x1 + 20, y1 + 12), title, font=F_H2, fill=WHITE)
    y = y1 + 82
    for item in items:
        item_h = max(62, len(wrap_text(draw, item, F_BODY, x2 - x1 - 74)) * 27 + 28)
        rounded(draw, (x1 + 18, y, x2 - 18, y + item_h), PALE, "#c4d7e2", 2, 11)
        draw.ellipse((x1 + 32, y + 20, x1 + 46, y + 34), fill=accent)
        draw_wrapped(draw, item, (x1 + 58, y + 18), x2 - x1 - 94, F_BODY, INK, 7)
        y += item_h + 14


def header(draw: ImageDraw.ImageDraw, title: str, subtitle: str) -> None:
    tw, _ = text_size(draw, title, F_TITLE)
    sw, _ = text_size(draw, subtitle, F_SUBTITLE)
    draw.text(((WIDTH - tw) // 2, 24), title, font=F_TITLE, fill=NAVY)
    draw.text(((WIDTH - sw) // 2, 94), subtitle, font=F_SUBTITLE, fill=MUTED)


def benefits(draw: ImageDraw.ImageDraw, items: list[tuple[str, str]], y: int, accent: str = GREEN) -> None:
    bottom = HEIGHT - 36
    rounded(draw, (36, y, WIDTH - 36, bottom), "#fbfefd", accent, 3, 16)
    draw.rectangle((36, y, 90, bottom), fill=accent)
    label_font = F_H3 if bottom - y < 130 else F_H2
    _, label_h = text_size(draw, "优", label_font)
    label_y = y + ((bottom - y) - label_h * 2 - 12) // 2
    draw.text((50, label_y), "优", font=label_font, fill=WHITE)
    draw.text((50, label_y + label_h + 12), "势", font=label_font, fill=WHITE)
    x = 116
    col_w = (WIDTH - 170) // len(items)
    for title, body in items:
        draw.text((x, y + 28), title, font=F_H3, fill=accent)
        draw_wrapped(draw, body, (x, y + 68), col_w - 26, F_SMALL, MUTED, 6)
        x += col_w


def render_three_column(diagram: dict, output: Path) -> None:
    img = Image.new("RGB", (WIDTH, HEIGHT), WHITE)
    draw = ImageDraw.Draw(img)
    header(draw, diagram["title"], diagram["subtitle"])

    boxes = [(32, 144, 468, 760), (550, 144, 986, 760), (1068, 144, 1504, 760)]
    accents = [GREEN, TEAL, BLUE]
    for idx, (box, section, accent) in enumerate(zip(boxes, diagram["sections"], accents)):
        items = list(section["items"])
        if idx == 2 and diagram.get("callout"):
            items.append(f"{diagram['callout'][0]}：{diagram['callout'][1]}")
        panel(draw, box, section["title"], items, accent)
    arrow(draw, (486, 450), (532, 450))
    arrow(draw, (1004, 450), (1050, 450))

    benefits(draw, diagram["benefits"], 786, diagram.get("benefit_accent", GREEN))
    img.save(output)


def render_lifecycle(output: Path) -> None:
    img = Image.new("RGB", (WIDTH, HEIGHT), WHITE)
    draw = ImageDraw.Draw(img)
    header(draw, "Frame Diff 生命周期", "PTY 输出 -> Rust 损伤跟踪 -> JSON diff -> Dart 合并 -> Flutter 行缓存渲染")
    cards = [
        ("1. PTY 输出", "shell output\nbytes\nresize / scroll / input response", GREEN),
        ("2. Rust 解析与损伤记录", "Terminal.process\n记录 dirty_rows\n记录 scroll_region", TEAL),
        ("3. 对比旧基线", "旧 rows\n基线元数据\n回退原因", BLUE),
        ("4. 生成 TerminalFrameDiff", "frame_kind: delta\nrows: changed only\nviewport_row_shift", ORANGE),
        ("5. Dart Runtime 应用", "takeFrameDiffJson()\ndecode\napplyFrame", TEAL),
        ("6. Viewport 渲染", "dirty rows rebuild\nrow visual cache\ncursor overlay", GREEN),
    ]
    positions = [
        (48, 170), (548, 170), (1048, 170),
        (48, 500), (548, 500), (1048, 500),
    ]
    w = 440
    h = 250
    for i, ((title, body, accent), (x, y)) in enumerate(zip(cards, positions)):
        rounded(draw, (x, y, x + w, y + h), WHITE, accent, 3, 16)
        draw.rectangle((x, y, x + w, y + 54), fill=accent)
        draw.rounded_rectangle((x, y, x + w, y + 70), radius=16, fill=accent)
        draw.rectangle((x, y + 54, x + w, y + 70), fill=WHITE)
        draw_wrapped(draw, title, (x + 20, y + 12), w - 40, F_H3, WHITE, 4)
        draw_wrapped(draw, body, (x + 22, y + 84), w - 44, F_BODY, MUTED, 8)
        if i in (1, 2, 5):
            mini_grid(draw, x + 250, y + 114, cols=8, rows=6, cell=13, highlights=(2, 4), color="#f59e0b" if i == 2 else "#27b7ad")
    arrow(draw, (488, 295), (532, 295))
    arrow(draw, (988, 295), (1032, 295))
    arrow(draw, (1268, 420), (1268, 485))
    arrow(draw, (1048, 625), (1004, 625))
    arrow(draw, (548, 625), (504, 625))
    rounded(draw, (48, 802, WIDTH - 48, 940), "#fffdf7", ORANGE, 3, 13)
    draw.text((90, 830), "核心原则：全量状态是安全基线，局部变化是高频快速路径。", font=F_H2, fill="#8a5600")
    draw_wrapped(draw, "Snapshot 负责重新对齐尺寸、模式、元数据和 scrollback；Delta 负责普通输出下的增量更新，减少传输与绘制。", (90, 880), 1300, F_BODY, MUTED, 6)
    img.save(output)


def render_snapshot_delta(output: Path) -> None:
    img = Image.new("RGB", (WIDTH, HEIGHT), WHITE)
    draw = ImageDraw.Draw(img)
    header(draw, "Snapshot vs Delta：安全基线与快速路径", "Snapshot 负责全量同步全屏；Delta 负责高频局部更新")

    def snapshot_card(
        box: tuple[int, int, int, int],
        title: str,
        items: list[str],
        accent: str,
        fill: str,
        highlights: tuple[int, ...],
        grid_color: str,
    ) -> None:
        x1, y1, x2, y2 = box
        rounded(draw, box, fill, accent, 3, 16)
        draw.rectangle((x1, y1, x2, y1 + 52), fill=accent)
        draw.rounded_rectangle((x1, y1, x2, y1 + 68), radius=16, fill=accent)
        draw.rectangle((x1, y1 + 52, x2, y1 + 68), fill=fill)
        draw.text((x1 + 20, y1 + 12), title, font=F_H2, fill=WHITE)
        mini_grid(draw, x1 + 52, y1 + 136, cols=9, rows=9, cell=18, highlights=highlights, color=grid_color)
        y = y1 + 88
        text_x = x1 + 255
        for item in items:
            item_h = max(56, len(wrap_text(draw, item, F_BODY, x2 - text_x - 44)) * 27 + 22)
            rounded(draw, (text_x, y, x2 - 24, y + item_h), PALE, "#c4d7e2", 2, 10)
            draw.ellipse((text_x + 14, y + 20, text_x + 28, y + 34), fill=accent)
            draw_wrapped(draw, item, (text_x + 40, y + 16), x2 - text_x - 74, F_BODY, INK, 7)
            y += item_h + 12

    snapshot_card(
        (32, 150, 560, 650),
        "Snapshot 全量同步",
        ["rows = 全屏", "用于首帧、resize、模式切换", "优点：强一致", "成本：传输和绘制更多"],
        ORANGE,
        "#fffaf2",
        (0, 1, 2, 3, 4, 5, 6, 7, 8),
        "#f59e0b",
    )
    snapshot_card(
        (976, 150, 1504, 650),
        "Delta 局部更新",
        ["rows = 变化行", "dirty_ranges 标记范围", "滚屏位移复用缓存", "优点：轻量快速"],
        TEAL,
        "#f1fbfb",
        (3, 7),
        "#27b7ad",
    )
    panel(draw, (620, 190, 916, 610), "Rust 判断路径", [
        "尺寸变化 -> 全量",
        "模式变化 -> 全量",
        "元数据不一致 -> 全量",
        "无回退原因 -> Delta",
    ], BLUE)
    arrow(draw, (596, 400), (620, 400), ORANGE)
    arrow(draw, (916, 400), (954, 400), TEAL)
    rounded(draw, (32, 700, 1504, 950), PALE_BLUE, BLUE, 3, 15)
    draw.text((62, 728), "示例：row 3 与 row 8 更新，viewport 上移 +1", font=F_H2, fill=NAVY)
    mini_grid(draw, 280, 790, cols=10, rows=7, cell=18, highlights=(3, 6), color="#64748b")
    draw_wrapped(draw, "Before：rows 0-9 已缓存\nincoming rows：row 3 / row 8\ndirty_ranges：[3..3], [8..8]\nnew state = shift(old rows) + incoming rows + dirty_ranges", (560, 780), 420, F_BODY, INK, 7)
    arrow(draw, (1010, 835), (1090, 835), BLUE, 6)
    mini_grid(draw, 1130, 790, cols=10, rows=7, cell=18, highlights=(3, 6), color="#27b7ad")
    img.save(output)


def render_benefits(output: Path) -> None:
    img = Image.new("RGB", (WIDTH, HEIGHT), WHITE)
    draw = ImageDraw.Draw(img)
    header(draw, "Frame Diff 的收益", "减少传输、减少合并、减少重绘，同时保留安全回退")
    rows = [
        ("1. 传输层：JSON 更小", "传统全量帧：每次发送全屏 rows", "Frame Diff：只发送变化行、dirty_ranges 与必要元数据"),
        ("2. Runtime 层：状态合并更轻", "传统方式：替换整个 viewport state", "Frame Diff：复用旧 frame，合并 delta rows 与滚屏位移"),
        ("3. Render 层：行缓存复用", "传统方式：全部行重新布局与绘制", "Frame Diff：只 rebuild dirty rows，clean rows 直接复用缓存"),
        ("4. 正确性：不确定就回退", "风险：丢行、错行、模式错乱", "保护：记录 fallback reason，resize / mode / metadata 变化时回退 snapshot"),
    ]
    y = 150
    for title, left, right in rows:
        rounded(draw, (36, y, 1500, y + 165), "#fbfdff", "#3b5368", 2, 14)
        draw.rectangle((36, y, 280, y + 165), fill="#26384a")
        draw_wrapped(draw, title, (58, y + 28), 198, F_H3, WHITE, 7)
        rounded(draw, (320, y + 26, 700, y + 138), "#fffaf2", ORANGE, 2, 12)
        rounded(draw, (860, y + 26, 1470, y + 138), "#f0fbfb", TEAL, 2, 12)
        draw_wrapped(draw, left, (342, y + 48), 330, F_BODY, INK, 7)
        arrow(draw, (730, y + 82), (820, y + 82), TEAL, 7)
        draw_wrapped(draw, right, (884, y + 48), 540, F_BODY, INK, 7)
        y += 178
    benefits(draw, [
        ("高频输出走 Delta", "只传变化、轻合并、少重绘。"),
        ("结构变化走 Snapshot", "遇到不确定状态先保证一致性。"),
        ("结果", "终端滚屏更顺，CPU 与绘制压力更低。"),
    ], 890, TEAL)
    img.save(output)


THREE_COLUMN = {
    "principle": {
        "path": OUT_DIRS["frame"] / "principle-advantages.png",
        "title": "Frame Diff 原理与优势",
        "subtitle": "Rust 端只发变化，Dart 端合并状态，Flutter 端只重建必要行",
        "sections": [
            {"title": "1. Rust native core 生成 diff", "items": ["损伤记录：变化行与滚屏区域", "缓存上次 rows 与元数据", "判断 snapshot 或 delta，输出 diff", "只携带变化行与必要元数据"]},
            {"title": "2. Dart runtime 合并状态", "items": ["接收 JSON diff", "RuntimeController 解码、路由、合并", "ViewportController 应用 snapshot / delta", "更新 cursor、modes、回看位移、metadata"]},
            {"title": "3. Flutter 渲染必要行", "items": ["滚屏时搬移可复用行缓存", "计算真正需要更新的行", "复用行视觉缓存，未变化行直接上屏", "selection / search / cursor 独立叠加"]},
        ],
        "benefits": [("更少 JSON", "只传变化行，显著减少序列化开销。"), ("更少合并成本", "Dart 只合并变化与元数据。"), ("更少绘制成本", "行缓存复用，dirty 行最小化绘制。"), ("滚屏更稳", "viewport_row_shift 搬移缓存，保持流畅。")],
        "callout": ("回退保护", "尺寸、模式、回看或元数据不一致时，回退 Snapshot。"),
        "middle_grid": True,
        "grid_rows": (3, 5),
    },
    "shell_hook": {
        "path": OUT_DIRS["feature"] / "shell-hook.png",
        "title": "Shell Hook 感知终端",
        "subtitle": "命令、目录、状态与标题，随 shell 上下文同步",
        "sections": [
            {"title": "1. Shell 事件来源", "items": ["Prompt Start：用户即将输入命令", "Command Entered：记录提交的命令", "CWD Changed：切换工作目录", "Command Exit：返回 exit_code 与耗时", "Window Title Update：同步 shell 或应用标题"]},
            {"title": "2. Native / Runtime 归因", "items": ["标准化事件并附加 session_id", "保留 timestamp、cwd、command、exit_code", "按会话路由，合并成可追溯的上下文", "统一字段：session、cwd、命令、shell"]},
            {"title": "3. Flutter 体验层", "items": ["Tab Title：目录、命令和状态驱动标题", "Recent Commands：最近命令列表和结果状态", "CWD Badge：当前工作目录始终可见", "Diagnostics Context：导出诊断时自动带上下文", "Replay Anchor：用事件锚定关键节点"]},
        ],
        "benefits": [("更少盲猜", "上下文由 shell 事件驱动，减少对输出文本的猜测。"), ("标签状态更清楚", "目录、命令、退出码映射到标签与状态条。"), ("诊断更可依", "导出时带命令、目录、时间和退出状态。"), ("可继续扩展", "为搜索、统计和自动化工作流留下接口。")],
        "callout": ("回退保护", "shell hook 不可用时，仍保留基础终端输出，不影响正常使用。"),
        "terminal": ["rob@mac ~ % git status", "exit 0  (12.4ms)", "cwd  ~/flutterm/src", "title flutterm - zsh"],
    },
    "row_cache": {
        "path": OUT_DIRS["feature"] / "row-cache.png",
        "title": "行级渲染缓存",
        "subtitle": "只重建变化行，未变化行复用视觉结果",
        "sections": [
            {"title": "1. 输入变化", "items": ["Frame Diff 提供更新信号", "dirty_ranges 标出发生内容变化的行", "viewport_row_shift 表示滚屏位移", "modes / metadata 影响独立覆盖层"]},
            {"title": "2. 缓存索引", "items": ["行视觉缓存保存布局与绘制结果", "Row Key = 行号 + 属性 + 文本哈希", "稳定行 key 不变，直接复用已有缓存", "脏行 key 变化，标记为需要重新布局"]},
            {"title": "3. Flutter 绘制", "items": ["接收更新信号并决定绘制范围", "dirty 行重新布局和绘制", "clean 行复用缓存，直接上屏", "cursor、selection、search、IME 独立叠加"]},
        ],
        "benefits": [("更少布局调用", "只计算脏行，避免全量行重排。"), ("更少 CPU/GPU 工作", "复用绘制结果，降低合成成本。"), ("滚动更顺", "行高度稳定，滚屏追踪更清楚。"), ("更易分析优化", "缓存命中率可观测，性能瓶颈更清晰。")],
        "callout": ("安全边界", "resize、字体、主题、元数据变化会清空或重建缓存，保证正确性。"),
        "middle_grid": True,
        "grid_rows": (2, 5),
        "grid_color": "#f59e0b",
    },
    "input_modes": {
        "path": OUT_DIRS["feature"] / "input-modes.png",
        "title": "模式感知输入系统",
        "subtitle": "按当前终端模式编码键盘、粘贴、鼠标与滚动",
        "sections": [
            {"title": "1. 输入来源", "items": ["键盘输入：按键、组合键、快捷键", "粘贴：单行、多行文本和命令", "鼠标事件：点击、移动、拖拽、选择", "滚轮滚动：上下滚动和水平滚动", "IME 输入：中文、日文等输入法"]},
            {"title": "2. 模式读取", "items": ["Bracketed Paste：识别是否启用括号粘贴", "Application Cursor：区分应用光标和普通光标", "Mouse Reporting：识别鼠标上报协议", "Alternate Screen：识别备用屏幕", "Focus Events：识别焦点变化"]},
            {"title": "3. 编码输出", "items": ["键盘编码：普通按键与组合键转义序列", "粘贴编码：启用时包裹括号粘贴标记", "鼠标编码：按协议发送位置、按键、修饰键", "滚轮编码：备用屏幕下转为按键", "IME 编码：按 UTF-8 写入终端"]},
        ],
        "benefits": [("Vim", "应用光标模式下移动键行为正确。"), ("Tmux", "括号粘贴保留整段文本。"), ("Less", "备用屏幕下滚轮转为上下键。"), ("Shell 提示符", "普通输入路径保持简单可靠。")],
        "callout": ("回退保护", "无法识别或读取模式时，走普通输入路径，避免误编码导致应用异常。"),
        "terminal": ["-- INSERT --", "tmux:~$ paste", "less file.txt", "user@mac ~ $"],
    },
    "instant_replay": {
        "path": OUT_DIRS["feature"] / "instant-replay.png",
        "title": "Instant Replay 轻量回放",
        "subtitle": "用轻量文本快照回看最近终端画面",
        "sections": [
            {"title": "1. 采集", "items": ["viewport rows：当前可视区域文本", "cursor：光标位置、形态和可见性", "modes：应用光标、插入模式、反向视频", "scrollback_offset：当前回看偏移", "command context：关联命令和退出状态"]},
            {"title": "2. 环形缓冲", "items": ["last N frames：只保留最近帧", "compact text：去重和压缩存储", "timestamp：按时间顺序排列", "command context：关联相关命令", "不录制视频，只保存文本和状态"]},
            {"title": "3. 回放入口", "items": ["跳转到最近输出：从时间轴选择任意时刻", "前后对比：查看变化行和 diff 高亮", "附带诊断上下文：命令、目录、时间、exit_code", "复现问题更快：一键定位关键画面"]},
        ],
        "benefits": [("低存储成本", "只存文本与状态，适合长期保留。"), ("易于分享协作", "JSON 快照体积小，可复制、粘贴、上传。"), ("定位问题更高效", "快速回看前后画面，减少排障成本。"), ("不改变 Shell 行为", "后台采集，不注入命令，不影响输出。")],
        "callout": ("边界说明", "不是录屏；不采集敏感输入；可按配置清理历史，保护隐私与空间。"),
        "terminal": ["#496 21:30:15", "#497 21:30:16", "#498 21:30:17", "#500 latest"],
    },
}


def render_manifest(diagrams: list[dict]) -> None:
    manifest = {
        "font": str(FONT_PATH),
        "note": "All diagram text is rendered from this script with system Chinese fonts.",
        "images": [],
    }
    for diagram in diagrams:
        manifest["images"].append(
            {
                "path": str(diagram["path"].relative_to(ROOT)),
                "title": diagram["title"],
                "subtitle": diagram["subtitle"],
                "sections": diagram.get("sections", []),
                "benefits": diagram.get("benefits", []),
                "callout": diagram.get("callout"),
            }
        )
    (ROOT / "assets" / "images" / "diagram-text-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    for out_dir in OUT_DIRS.values():
        out_dir.mkdir(parents=True, exist_ok=True)
    render_three_column(THREE_COLUMN["principle"], THREE_COLUMN["principle"]["path"])
    render_lifecycle(OUT_DIRS["frame"] / "lifecycle.png")
    render_snapshot_delta(OUT_DIRS["frame"] / "snapshot-delta.png")
    render_benefits(OUT_DIRS["frame"] / "benefits.png")
    for key in ("shell_hook", "row_cache", "input_modes", "instant_replay"):
        render_three_column(THREE_COLUMN[key], THREE_COLUMN[key]["path"])
    render_manifest(
        [
            THREE_COLUMN["principle"],
            {
                "path": OUT_DIRS["frame"] / "lifecycle.png",
                "title": "Frame Diff 生命周期",
                "subtitle": "PTY 输出 -> Rust 损伤跟踪 -> JSON diff -> Dart 合并 -> Flutter 行缓存渲染",
            },
            {
                "path": OUT_DIRS["frame"] / "snapshot-delta.png",
                "title": "Snapshot vs Delta：安全基线与快速路径",
                "subtitle": "Snapshot 负责全量同步全屏；Delta 负责高频局部更新",
            },
            {
                "path": OUT_DIRS["frame"] / "benefits.png",
                "title": "Frame Diff 的收益",
                "subtitle": "减少传输、减少合并、减少重绘，同时保留安全回退",
            },
            THREE_COLUMN["shell_hook"],
            THREE_COLUMN["row_cache"],
            THREE_COLUMN["input_modes"],
            THREE_COLUMN["instant_replay"],
        ]
    )


if __name__ == "__main__":
    main()
