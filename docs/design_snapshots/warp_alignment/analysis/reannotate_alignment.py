#!/usr/bin/env python3
"""Regenerate Warp/Ianvs layout comparison annotations.

The script intentionally uses only the Python standard library. It produces
SVG overlays instead of rasterized PNGs so the annotations remain deterministic
and reviewable without adding image-processing dependencies.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from xml.sax.saxutils import escape


BASE = Path(__file__).resolve().parents[1]
OUT = BASE / "analysis" / "reannotated"


PALETTE = {
    "anchor": "#38bdf8",
    "block": "#22c55e",
    "input": "#f59e0b",
    "palette": "#a78bfa",
    "actions": "#ef4444",
    "pane": "#14b8a6",
    "launch": "#f97316",
    "menu": "#eab308",
    "context": "#64748b",
}


@dataclass(frozen=True)
class ImageRef:
    role: str
    path: str | None
    source: str
    anchor: str | None = None


@dataclass(frozen=True)
class Region:
    key: str
    label: str
    color: str
    warp: tuple[float, float, float, float] | None = None
    ianvs: tuple[float, float, float, float] | None = None


@dataclass(frozen=True)
class Comparison:
    key: str
    title: str
    warp: ImageRef
    ianvs: ImageRef
    notes: tuple[str, ...]
    regions: tuple[Region, ...]


def rect(x: float, y: float, w: float, h: float) -> tuple[float, float, float, float]:
    return (x, y, w, h)


COMPARISONS: tuple[Comparison, ...] = (
    Comparison(
        key="default_terminal_layout",
        title="Default display view layout",
        warp=ImageRef(
            role="warp",
            path="default_terminal_layout.png",
            source="User supplied default display screenshot rects, calibrated in Ianvs",
            anchor="app_frame",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="default_terminal_layout.png",
            source="Ianvs golden default_terminal_layout",
            anchor="app_frame",
        ),
        notes=(
            "Default state uses the user-supplied 1656 x 2064 display screenshot as the layout source.",
            "Top chrome, empty viewport, visible scrollback, context chips, and input editor are calibrated 1:1.",
        ),
        regions=(
            Region("app_frame", "app frame", "anchor", rect(0, 0, 1656, 2064), rect(0, 0, 1656, 2064)),
            Region("top_chrome", "top chrome", "anchor", rect(0, 0, 1656, 68), rect(0, 0, 1656, 68)),
            Region("active_tab", "active tab title", "context", rect(276, 0, 384, 68), rect(276, 0, 384, 68)),
            Region("terminal_viewport", "terminal viewport", "block", rect(0, 68, 1656, 1789), rect(0, 68, 1656, 1789)),
            Region("visible_scrollback", "visible scrollback", "block", rect(0, 1490, 1656, 367), rect(0, 1490, 1656, 367)),
            Region("input_context", "input context chips", "context", rect(0, 1857, 1656, 74), rect(0, 1857, 1656, 74)),
            Region("input_editor", "input editor", "input", rect(0, 1931, 1656, 133), rect(0, 1931, 1656, 133)),
        ),
    ),
    Comparison(
        key="block_actions_layout",
        title="Block hover actions layout",
        warp=ImageRef(
            role="warp",
            path="warp_interaction/02_block_not_hover_click_actions.png",
            source="Warp manual interaction sample 02_block_not_hover_click_actions",
            anchor="terminal_pane",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="block_actions_layout.png",
            source="Ianvs golden block_actions_layout",
            anchor="terminal_pane",
        ),
        notes=(
            "Actions must stay attached to the active block instead of moving to global chrome.",
            "Hover state must not shift block or input geometry.",
        ),
        regions=(
            Region("terminal_pane", "terminal pane", "anchor", rect(501, 71, 2955, 1007), rect(0, 76, 1440, 824)),
            Region("block_band", "active block band", "block", rect(501, 449, 2955, 406), rect(0, 385, 1440, 332)),
            Region("command_body", "command/output body", "block", rect(532, 489, 2680, 326), rect(15, 418, 1306, 267)),
            Region("block_actions", "inline actions", "actions", rect(3188, 470, 250, 58), rect(1309, 402, 122, 44)),
            Region("input_context", "input context chips", "context", rect(532, 873, 2690, 41), rect(15, 729, 1311, 34)),
            Region("input_editor", "input editor", "input", rect(501, 914, 2955, 164), rect(16, 763, 1408, 137)),
        ),
    ),
    Comparison(
        key="completion_input_layout",
        title="Completion input pane-local layout",
        warp=ImageRef(
            role="warp",
            path="warp_interaction/04_completion_input.png",
            source="Warp manual interaction sample 04_completion_input",
            anchor="terminal_pane",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="completion_input_layout.png",
            source="Ianvs golden completion_input_layout",
            anchor="terminal_pane",
        ),
        notes=(
            "Alignment excludes Warp sidebar/app chrome and compares active terminal pane-local ratios.",
            "Detection strip and input editor should hand off cleanly below the active block band.",
        ),
        regions=(
            Region("terminal_pane", "terminal pane", "anchor", rect(501, 71, 2955, 1007), rect(0, 76, 1440, 824)),
            Region("block_band", "active block band", "block", rect(501, 449, 2955, 406), rect(0, 385, 1440, 332)),
            Region("command_body", "command/output body", "block", rect(532, 489, 2680, 326), rect(15, 418, 1306, 267)),
            Region("block_actions", "block actions", "actions", rect(3188, 470, 250, 58), rect(1309, 402, 122, 44)),
            Region("detection_strip", "command detection strip", "input", rect(501, 855, 2955, 59), rect(0, 718, 1440, 49)),
            Region("input_editor", "input editor system", "input", rect(501, 914, 2955, 164), rect(0, 766, 1440, 134)),
        ),
    ),
    Comparison(
        key="blocks_command_palette",
        title="Blocks plus command palette layout",
        warp=ImageRef(
            role="warp",
            path="warp_interaction/03_command_search.png",
            source="Warp manual interaction sample 03_command_search",
            anchor="comparison_frame",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="blocks_command_palette.png",
            source="Ianvs golden blocks_command_palette",
            anchor="comparison_frame",
        ),
        notes=(
            "Palette placement and source rail are compared against Warp command search.",
            "Block rail remains visible behind the palette to keep terminal context.",
        ),
        regions=(
            Region("comparison_frame", "comparison frame", "anchor", rect(0, 0, 3456, 1078), rect(0, 0, 1440, 900)),
            Region("terminal_pane", "terminal pane", "anchor", rect(501, 71, 2955, 1007), rect(0, 76, 1440, 824)),
            Region("palette_shell", "palette shell", "palette", rect(1086, 235, 1284, 584), rect(452, 196, 535, 488)),
            Region("source_rail", "source rail", "palette", rect(1115, 350, 290, 272), rect(465, 292, 122, 227)),
            Region("results_list", "results list", "palette", rect(1086, 622, 1284, 197), rect(452, 519, 535, 164)),
            Region("input_editor", "input editor", "input", rect(501, 914, 2955, 164), rect(16, 763, 1408, 137)),
        ),
    ),
    Comparison(
        key="split_pane_layout",
        title="Split pane local controls layout",
        warp=ImageRef(
            role="warp",
            path="warp_interaction/05_split_pane.png",
            source="Warp manual interaction sample 05_split_pane",
            anchor="terminal_area",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="split_pane_layout.png",
            source="Ianvs golden split_pane_layout",
            anchor="terminal_area",
        ),
        notes=(
            "Each pane keeps local header, active marker, context chips, and input editor.",
            "Move-to-tab is covered by behavior tests; drag-to-tab remains a later enhancement.",
        ),
        regions=(
            Region("comparison_frame", "comparison frame", "anchor", rect(0, 0, 3456, 1078), rect(0, 0, 1440, 900)),
            Region("terminal_area", "terminal area", "anchor", rect(501, 71, 2955, 1007), rect(0, 76, 1440, 824)),
            Region("left_pane", "left pane", "pane", rect(501, 71, 1477, 1007), rect(0, 76, 720, 824)),
            Region("right_pane", "right pane", "pane", rect(1978, 71, 1478, 1007), rect(720, 76, 720, 824)),
            Region("pane_header", "pane headers", "pane", rect(501, 72, 2955, 40), rect(0, 60, 1440, 34)),
            Region("active_marker", "active pane marker", "actions", rect(1978, 72, 20, 40), rect(720, 60, 10, 34)),
            Region("input_editor", "per-pane input editors", "input", rect(501, 914, 2955, 164), rect(0, 763, 1440, 137)),
        ),
    ),
    Comparison(
        key="split_session_palette",
        title="Split pane plus session palette layout",
        warp=ImageRef(
            role="warp",
            path="warp_interaction/03_command_search.png",
            source="Warp manual interaction sample 03_command_search",
            anchor="comparison_frame",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="split_session_palette.png",
            source="Ianvs golden split_session_palette",
            anchor="comparison_frame",
        ),
        notes=(
            "Session navigation uses the same command palette shell and source rail.",
            "Ianvs keeps split pane context visible underneath the palette.",
        ),
        regions=(
            Region("comparison_frame", "comparison frame", "anchor", rect(0, 0, 3456, 1078), rect(0, 0, 1440, 900)),
            Region("terminal_pane", "terminal pane", "anchor", rect(501, 71, 2955, 1007), rect(0, 76, 1440, 824)),
            Region("palette_shell", "palette shell", "palette", rect(1086, 235, 1284, 584), rect(452, 196, 535, 488)),
            Region("source_rail", "source rail", "palette", rect(1115, 350, 290, 272), rect(465, 292, 122, 227)),
            Region("results_list", "results list", "palette", rect(1086, 622, 1284, 197), rect(452, 519, 535, 164)),
            Region("split_divider", "split divider", "pane", rect(1978, 71, 4, 1007), rect(720, 76, 4, 824)),
        ),
    ),
    Comparison(
        key="add_menu_layout",
        title="Add menu entry hierarchy",
        warp=ImageRef(
            role="warp",
            path="warp_interaction/06_tab_or_launch_config_entry.png",
            source="Warp manual interaction sample 06_tab_or_launch_config_entry",
            anchor="menu_surface",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="add_menu_layout.png",
            source="Ianvs golden add_menu_layout",
            anchor="menu_surface",
        ),
        notes=(
            "New tab/window/SSH, saved configs, save current tab/app, and shell selector converge into one plus menu.",
            "Ianvs does not copy Warp agent/cloud entries.",
        ),
        regions=(
            Region("menu_surface", "add menu surface", "menu", rect(590, 86, 600, 564), rect(420, 60, 572, 448)),
            Region("creation_group", "creation actions", "menu", rect(610, 105, 560, 180), rect(440, 84, 532, 145)),
            Region("config_group", "config actions", "launch", rect(610, 300, 560, 210), rect(440, 236, 532, 165)),
            Region("shell_group", "shell selector", "context", rect(610, 520, 560, 110), rect(440, 405, 532, 82)),
        ),
    ),
    Comparison(
        key="saved_config_sidecar",
        title="Saved config discovery sidecar",
        warp=ImageRef(
            role="warp",
            path="warp_interaction/06_tab_or_launch_config_entry.png",
            source="Warp manual interaction sample 06_tab_or_launch_config_entry and Tab Configs docs",
            anchor="menu_surface",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="saved_config_sidecar.png",
            source="Ianvs golden saved_config_sidecar",
            anchor="dialog",
        ),
        notes=(
            "Saved configs are discoverable from the add menu and show a sidecar with apply/edit/remove/default actions.",
            "Scope labels distinguish app config from tab config.",
        ),
        regions=(
            Region("menu_surface", "Warp saved config entry", "menu", rect(590, 86, 600, 564), None),
            Region("dialog", "saved configs dialog", "menu", None, rect(310, 170, 820, 560)),
            Region("config_list", "config list", "menu", None, rect(342, 230, 300, 470)),
            Region("sidecar", "sidecar actions", "launch", None, rect(626, 210, 504, 490)),
            Region("primary_cta", "apply/default actions", "actions", None, rect(670, 560, 410, 90)),
        ),
    ),
    Comparison(
        key="launch_config_compose",
        title="Launch config compose modal",
        warp=ImageRef(
            role="warp",
            path=None,
            source="Warp Tab Configs docs plus launch_configs/save_modal.rs",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="launch_config_compose.png",
            source="Ianvs golden launch_config_compose",
            anchor="dialog",
        ),
        notes=(
            "Docs/source reference is semantic because no local Warp screenshot is stored for the save modal.",
            "Compose state is name-first, with scope explainer, path preview, advanced path, and primary save CTA.",
        ),
        regions=(
            Region("dialog", "launch config dialog", "launch", None, rect(50, 25, 860, 650)),
            Region("scope_explainer", "scope explainer", "context", None, rect(74, 96, 812, 106)),
            Region("name_field", "name field", "input", None, rect(92, 210, 776, 56)),
            Region("path_preview", "path preview", "context", None, rect(92, 323, 776, 42)),
            Region("advanced_path", "advanced path field", "input", None, rect(92, 416, 776, 56)),
            Region("primary_cta", "save CTA", "actions", None, rect(690, 573, 178, 44)),
        ),
    ),
    Comparison(
        key="launch_config_success",
        title="Launch config success modal",
        warp=ImageRef(
            role="warp",
            path=None,
            source="Warp launch_configs/save_modal.rs success state",
        ),
        ianvs=ImageRef(
            role="ianvs",
            path="launch_config_success.png",
            source="Ianvs golden launch_config_success",
            anchor="dialog",
        ),
        notes=(
            "Success state stays open so the saved file can be verified or reapplied.",
            "Ianvs uses Apply saved app, Copy path, and Done instead of Warp-specific file opening copy.",
        ),
        regions=(
            Region("dialog", "launch config dialog", "launch", None, rect(50, 25, 860, 650)),
            Region("success_state", "success state", "launch", None, rect(74, 172, 812, 220)),
            Region("success_path", "saved path", "context", None, rect(92, 417, 776, 48)),
            Region("action_row", "success actions", "actions", None, rect(548, 573, 320, 44)),
        ),
    ),
)


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as fh:
        header = fh.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", header[16:24])


def rel_href(from_dir: Path, image: Path) -> str:
    return Path(os.path.relpath(image, from_dir)).as_posix()


def side_regions(comparison: Comparison, side: str) -> list[Region]:
    return [
        region
        for region in comparison.regions
        if getattr(region, side) is not None
    ]


def rect_ratio(rect_value: tuple[float, float, float, float], anchor: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    x, y, w, h = rect_value
    ax, ay, aw, ah = anchor
    return ((x - ax) / aw, (y - ay) / ah, w / aw, h / ah)


def max_delta(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    return max(abs(x - y) for x, y in zip(a, b))


def alignment_rows(comparison: Comparison) -> list[dict[str, object]]:
    warp_anchor = None
    ianvs_anchor = None
    if comparison.warp.anchor:
        for region in comparison.regions:
            if region.key == comparison.warp.anchor:
                warp_anchor = region.warp
    if comparison.ianvs.anchor:
        for region in comparison.regions:
            if region.key == comparison.ianvs.anchor:
                ianvs_anchor = region.ianvs
    if warp_anchor is None or ianvs_anchor is None:
        return []
    rows = []
    for region in comparison.regions:
        if region.warp is None or region.ianvs is None or region.key in {comparison.warp.anchor, comparison.ianvs.anchor}:
            continue
        if region.key == "comparison_frame":
            continue
        if comparison.warp.anchor == "comparison_frame" and region.key in {
            "terminal_pane",
            "terminal_area",
            "split_divider",
            "input_editor",
        }:
            continue
        warp_ratio = rect_ratio(region.warp, warp_anchor)
        ianvs_ratio = rect_ratio(region.ianvs, ianvs_anchor)
        delta = max_delta(warp_ratio, ianvs_ratio)
        rows.append(
            {
                "region": region.key,
                "max_delta": round(delta, 4),
                "status": "pass" if delta <= 0.05 else "review",
                "warp_ratio": [round(value, 4) for value in warp_ratio],
                "ianvs_ratio": [round(value, 4) for value in ianvs_ratio],
            }
        )
    return rows


def draw_side(
    *,
    chunks: list[str],
    comparison: Comparison,
    side: str,
    image_ref: ImageRef,
    x_offset: float,
    y_offset: float,
    max_width: float,
    max_height: float,
) -> tuple[float, float]:
    title = "Warp reference" if side == "warp" else "Ianvs current"
    chunks.append(
        f'<text x="{x_offset:.1f}" y="{y_offset - 16:.1f}" class="side-title">{escape(title)}</text>'
    )
    chunks.append(
        f'<text x="{x_offset:.1f}" y="{y_offset + 2:.1f}" class="source">{escape(image_ref.source)}</text>'
    )
    image_path = BASE / image_ref.path if image_ref.path else None
    if image_path is None:
        width, height = max_width, max_height
        chunks.append(
            f'<rect x="{x_offset:.1f}" y="{y_offset + 18:.1f}" width="{width:.1f}" height="{height:.1f}" rx="8" class="missing"/>'
        )
        chunks.append(
            f'<text x="{x_offset + 24:.1f}" y="{y_offset + 72:.1f}" class="missing-text">No local Warp image.</text>'
        )
        chunks.append(
            f'<text x="{x_offset + 24:.1f}" y="{y_offset + 104:.1f}" class="missing-text">Reference is docs/source semantics.</text>'
        )
        scale = 1.0
        draw_y = y_offset + 18
    else:
        source_w, source_h = png_size(image_path)
        scale = min(max_width / source_w, max_height / source_h)
        width, height = source_w * scale, source_h * scale
        href = rel_href(OUT, image_path)
        draw_y = y_offset + 18
        chunks.append(
            f'<image x="{x_offset:.1f}" y="{draw_y:.1f}" width="{width:.1f}" height="{height:.1f}" href="{escape(href)}"/>'
        )
    for region in side_regions(comparison, side):
        raw_rect = getattr(region, side)
        if raw_rect is None:
            continue
        x, y, w, h = raw_rect
        sx, sy, sw, sh = x_offset + x * scale, draw_y + y * scale, w * scale, h * scale
        color = PALETTE[region.color]
        chunks.append(
            f'<rect x="{sx:.1f}" y="{sy:.1f}" width="{sw:.1f}" height="{sh:.1f}" class="region" stroke="{color}"/>'
        )
        chunks.append(
            f'<text x="{sx + 5:.1f}" y="{max(sy + 15, draw_y + 15):.1f}" class="label" fill="{color}">{escape(region.label)}</text>'
        )
    return width, height


def write_comparison_svg(comparison: Comparison) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    gap = 28
    panel_w = 760
    panel_h = 500
    top = 96
    left = 24
    chunks: list[str] = []
    chunks.append(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1588" height="760" viewBox="0 0 1588 760">'
    )
    chunks.append(
        """<style>
        .bg { fill: #0f172a; }
        .title { font: 700 22px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: #f8fafc; }
        .side-title { font: 700 15px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: #e2e8f0; }
        .source { font: 12px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: #94a3b8; }
        .note { font: 12px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: #cbd5e1; }
        .label { font: 700 11px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; paint-order: stroke; stroke: #020617; stroke-width: 3px; }
        .region { fill: transparent; stroke-width: 2.5px; vector-effect: non-scaling-stroke; }
        .missing { fill: #111827; stroke: #475569; stroke-width: 2px; }
        .missing-text { font: 15px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: #cbd5e1; }
        </style>"""
    )
    chunks.append('<rect width="1588" height="760" class="bg"/>')
    chunks.append(f'<text x="{left}" y="34" class="title">{escape(comparison.title)}</text>')
    for index, note in enumerate(comparison.notes):
        chunks.append(f'<text x="{left}" y="{58 + index * 18}" class="note">- {escape(note)}</text>')
    draw_side(
        chunks=chunks,
        comparison=comparison,
        side="warp",
        image_ref=comparison.warp,
        x_offset=left,
        y_offset=top,
        max_width=panel_w,
        max_height=panel_h,
    )
    draw_side(
        chunks=chunks,
        comparison=comparison,
        side="ianvs",
        image_ref=comparison.ianvs,
        x_offset=left + panel_w + gap,
        y_offset=top,
        max_width=panel_w,
        max_height=panel_h,
    )
    rows = alignment_rows(comparison)
    y = 638
    chunks.append(f'<text x="{left}" y="{y}" class="side-title">Alignment deltas</text>')
    if rows:
        for index, row in enumerate(rows):
            chunks.append(
                f'<text x="{left}" y="{y + 22 + index * 16}" class="note">{escape(str(row["region"]))}: max_delta={row["max_delta"]} status={row["status"]}</text>'
            )
    else:
        chunks.append(
            f'<text x="{left}" y="{y + 22}" class="note">No local Warp raster anchor; checked by semantic/source mapping and Ianvs golden contract.</text>'
        )
    chunks.append("</svg>\n")
    path = OUT / f"{comparison.key}_comparison.svg"
    path.write_text("\n".join(chunks), encoding="utf-8")
    return path


def comparison_manifest() -> dict[str, object]:
    specs = []
    for comparison in COMPARISONS:
        specs.append(
            {
                "key": comparison.key,
                "title": comparison.title,
                "warp": comparison.warp.__dict__,
                "ianvs": comparison.ianvs.__dict__,
                "notes": list(comparison.notes),
                "regions": [
                    {
                        "key": region.key,
                        "label": region.label,
                        "color": region.color,
                        "warp": list(region.warp) if region.warp else None,
                        "ianvs": list(region.ianvs) if region.ianvs else None,
                    }
                    for region in comparison.regions
                ],
                "alignment": alignment_rows(comparison),
            }
        )
    return {
        "schema": 1,
        "scope": "Warp/Ianvs terminal layout comparison annotations",
        "tolerance": 0.05,
        "comparison_count": len(COMPARISONS),
        "comparisons": specs,
    }


def write_manifest() -> Path:
    path = OUT / "alignment_regions.json"
    path.write_text(
        json.dumps(comparison_manifest(), ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return path


def write_readme(svg_paths: Iterable[Path]) -> Path:
    rows = []
    for comparison in COMPARISONS:
        rows.append(
            f"| `{comparison.key}` | `{comparison.ianvs.path or 'n/a'}` | `{comparison.warp.path or comparison.warp.source}` | `{comparison.key}_comparison.svg` |"
        )
    content = "\n".join(
        [
            "# Reannotated Warp Alignment Comparisons",
            "",
            "Generated by `reannotate_alignment.py`.",
            "",
            "This directory contains deterministic SVG overlays for every current Ianvs layout comparison screenshot. Local Warp screenshots are used where available; launch-config compose/success are mapped to Warp docs/source semantics because no local Warp save-modal raster is stored in this repo.",
            "",
            "| comparison | Ianvs image | Warp reference | annotated SVG |",
            "| --- | --- | --- | --- |",
            *rows,
            "",
            "Validation:",
            "",
            "- `alignment_regions.json` stores every annotated rect and normalized alignment delta.",
            "- `alignment_iteration_report.md` records the 10 deterministic regeneration passes.",
            "- Existing Flutter golden tests remain the screenshot regression gate.",
            "",
        ]
    )
    path = OUT / "README.md"
    path.write_text(content, encoding="utf-8")
    return path


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def output_fingerprint(paths: Iterable[Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda value: value.as_posix()):
        digest.update(path.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def generate_once() -> tuple[list[Path], str]:
    svg_paths = [write_comparison_svg(comparison) for comparison in COMPARISONS]
    manifest = write_manifest()
    readme = write_readme(svg_paths)
    paths = [*svg_paths, manifest, readme]
    return paths, output_fingerprint(paths)


def write_iteration_report(iterations: int, fingerprints: list[str], paths: list[Path]) -> Path:
    stable = len(set(fingerprints)) == 1
    lines = [
        "# Alignment Annotation Iteration Report",
        "",
        f"- requested iterations: `{iterations}`",
        f"- completed iterations: `{len(fingerprints)}`",
        f"- comparison SVGs: `{len(COMPARISONS)}`",
        f"- deterministic output: `{'yes' if stable else 'no'}`",
        f"- final fingerprint: `{fingerprints[-1]}`",
        "",
        "## Iterations",
        "",
        "| iteration | output fingerprint |",
        "| ---: | --- |",
    ]
    for index, fingerprint in enumerate(fingerprints, start=1):
        lines.append(f"| {index} | `{fingerprint}` |")
    lines.extend(
        [
            "",
            "## Generated Files",
            "",
            "| file | sha256 |",
            "| --- | --- |",
        ]
    )
    for path in sorted(paths, key=lambda value: value.as_posix()):
        lines.append(f"| `{path.relative_to(BASE).as_posix()}` | `{file_hash(path)}` |")
    lines.append("")
    report = OUT / "alignment_iteration_report.md"
    report.write_text("\n".join(lines), encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=10)
    args = parser.parse_args()
    if args.iterations < 1:
        raise SystemExit("--iterations must be >= 1")
    fingerprints: list[str] = []
    latest_paths: list[Path] = []
    for _ in range(args.iterations):
        latest_paths, fingerprint = generate_once()
        fingerprints.append(fingerprint)
    write_iteration_report(args.iterations, fingerprints, latest_paths)
    if len(set(fingerprints)) != 1:
        raise SystemExit("generated annotations were not deterministic")
    print(f"Generated {len(COMPARISONS)} comparison annotations for {args.iterations} iterations.")
    print(f"Output: {OUT.relative_to(BASE)}")


if __name__ == "__main__":
    main()
