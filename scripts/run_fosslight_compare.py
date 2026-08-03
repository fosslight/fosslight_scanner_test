#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
Run FOSSLight BOM compare (same logic/table as `fosslight compare`) and print a Markdown table.

Uses fosslight_util.read_excel.read_oss_report + fosslight_util.compare_yaml.compare_yaml,
matching fosslight_scanner._run_compare.parse_result_for_table columns:

  Status | Before OSS | Before License | After OSS | After License
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from fosslight_util.compare_yaml import compare_yaml
from fosslight_util.read_excel import read_oss_report

ADD = "add"
DELETE = "delete"
CHANGE = "change"
COMP_STATUS = (ADD, DELETE, CHANGE)


def _escape_md(value: Any, max_len: int = 100) -> str:
    text = "" if value is None else str(value)
    text = text.replace("\n", " ").replace("|", "\\|").replace("`", "'")
    if len(text) > max_len:
        return text[: max_len - 1] + "…"
    return text


def parse_result_for_table(oi: dict, status: str) -> list[str]:
    """Same row layout as fosslight_scanner._run_compare.parse_result_for_table."""
    if status in (ADD, DELETE):
        oi_ver = "" if oi.get("version", "") == "" else f"({oi['version']})"
        oss_info = f"{oi.get('name', '')}{oi_ver}"
        license_info = ", ".join(oi.get("license", []) or [])
        if status == ADD:
            return [status, "", "", oss_info, license_info]
        return [status, oss_info, license_info, "", ""]

    if status == CHANGE:
        oss_before, oss_after, license_before, license_after = [], [], [], []
        name = oi.get("name", "")
        for prev_i in oi.get("prev", []):
            prev_ver = "" if prev_i.get("version", "") == "" else f"({prev_i['version']})"
            oss_before.append(f"{name}{prev_ver}")
            license_before.append(", ".join(prev_i.get("license", []) or []))
        for now_i in oi.get("now", []):
            now_ver = "" if now_i.get("version", "") == "" else f"({now_i['version']})"
            oss_after.append(f"{name}{now_ver}")
            license_after.append(", ".join(now_i.get("license", []) or []))
        return [
            status,
            " / ".join(oss_before),
            " / ".join(license_before),
            " / ".join(oss_after),
            " / ".join(license_after),
        ]

    raise ValueError(f"Unsupported compare status: {status}")


def run_compare(before_xlsx: Path, after_xlsx: Path) -> dict[str, list]:
    before_items = read_oss_report(str(before_xlsx), "", str(before_xlsx.parent))
    after_items = read_oss_report(str(after_xlsx), "", str(after_xlsx.parent))
    result = compare_yaml(before_items, after_items)
    if result == "" or result is None:
        return {ADD: [], DELETE: [], CHANGE: []}
    return result


def count_summary(compared: dict[str, list]) -> str:
    lengths = [len(compared.get(st, [])) for st in COMP_STATUS]
    total = sum(lengths)
    if total == 0:
        return "all oss lists are the same."
    detail = ", ".join(f"{COMP_STATUS[i]}: {lengths[i]}" for i in range(3))
    return f"total {total} oss updated ({detail})"


def format_markdown(compared: dict[str, list]) -> str:
    summary = count_summary(compared)
    rows: list[list[str]] = []
    for status in COMP_STATUS:
        for oi in compared.get(status, []):
            rows.append(parse_result_for_table(oi, status))

    lines = [
        f"Comparison result (fosslight compare): **{summary}**",
        "",
    ]
    if not rows:
        lines.append("No BOM differences (add / delete / change).")
        lines.append("")
        return "\n".join(lines)

    lines.extend(
        [
            f"Found **{len(rows)}** BOM difference row(s).",
            "",
            "| # | Status | Before OSS | Before License | After OSS | After License |",
            "|---|--------|------------|----------------|-----------|---------------|",
        ]
    )
    for i, row in enumerate(rows, 1):
        status, before_oss, before_lic, after_oss, after_lic = row
        lines.append(
            "| {num} | {status} | {b_oss} | {b_lic} | {a_oss} | {a_lic} |".format(
                num=i,
                status=_escape_md(status, 20),
                b_oss=_escape_md(before_oss),
                b_lic=_escape_md(before_lic),
                a_oss=_escape_md(after_oss),
                a_lic=_escape_md(after_lic),
            )
        )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before_excel", type=Path, help="PyPI (before) FOSSLight report xlsx")
    parser.add_argument("after_excel", type=Path, help="GitHub (after) FOSSLight report xlsx")
    parser.add_argument("-o", "--output-json", type=Path, help="Write raw compare JSON")
    parser.add_argument("--md", type=Path, help="Write Markdown table")
    args = parser.parse_args()

    if not args.before_excel.is_file():
        print(f"ERROR: before excel not found: {args.before_excel}", file=sys.stderr)
        return 2
    if not args.after_excel.is_file():
        print(f"ERROR: after excel not found: {args.after_excel}", file=sys.stderr)
        return 2

    compared = run_compare(args.before_excel, args.after_excel)
    md_text = format_markdown(compared)
    print(md_text, end="")

    if args.output_json:
        args.output_json.parent.mkdir(parents=True, exist_ok=True)
        args.output_json.write_text(json.dumps(compared, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"Wrote JSON: {args.output_json}")

    if args.md:
        args.md.parent.mkdir(parents=True, exist_ok=True)
        args.md.write_text(md_text, encoding="utf-8")
        print(f"Wrote Markdown: {args.md}")

    total = sum(len(compared.get(st, [])) for st in COMP_STATUS)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
