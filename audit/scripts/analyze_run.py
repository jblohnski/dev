#!/usr/bin/env python3
"""Analyze baseline/current snapshots and write normalized diff + summaries."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path


VOLATILE_PATTERNS = [
    re.compile(r"^\+\+\+ .*"),
    re.compile(r"^--- .*"),
    re.compile(r"^[+-]?Generated:\s"),
    re.compile(r"^[+-]?[A-Z][a-z]{2} [A-Z][a-z]{2} [ 0-9]{2} "),
    re.compile(r"^[+-]?\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"),
    re.compile(r"^[+-]?\s*Time(stamp)?\s*:"),
]

SUSPECT_PAT = re.compile(r"\[sus\]|suspicious|anomaly|invalid|not signed", re.IGNORECASE)


def run_diff(baseline: Path, current: Path) -> str:
    proc = subprocess.run(
        ["diff", "-ru", str(baseline), str(current)],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode not in (0, 1):
        raise RuntimeError(proc.stderr.strip() or "diff failed")
    return proc.stdout


def normalize_diff(raw: str) -> list[str]:
    out: list[str] = []
    for line in raw.splitlines():
        if any(p.search(line) for p in VOLATILE_PATTERNS):
            continue
        out.append(line)
    return out


def diff_stats(lines: list[str]) -> dict[str, int]:
    added = 0
    removed = 0
    hunks = 0
    files_changed = 0
    only_in = 0
    for line in lines:
        if line.startswith("diff -ru "):
            files_changed += 1
        elif line.startswith("@@"):
            hunks += 1
        elif line.startswith("+") and not line.startswith("+++"):
            added += 1
        elif line.startswith("-") and not line.startswith("---"):
            removed += 1
        elif line.startswith("Only in "):
            only_in += 1
    return {
        "files_changed": files_changed,
        "hunks": hunks,
        "added_lines": added,
        "removed_lines": removed,
        "only_in_entries": only_in,
    }


def collect_suspicions(current: Path, limit: int = 40) -> list[str]:
    findings: list[str] = []
    for file in sorted(current.rglob("*")):
        if not file.is_file():
            continue
        if file.suffix not in {".txt", ".log"}:
            continue
        try:
            with file.open("r", encoding="utf-8", errors="replace") as fh:
                for idx, line in enumerate(fh, start=1):
                    if SUSPECT_PAT.search(line):
                        rel = file.relative_to(current)
                        findings.append(f"{rel}:{idx}: {line.strip()}")
                        if len(findings) >= limit:
                            return findings
        except OSError:
            continue
    return findings


def risk_level(stats: dict[str, int], findings: list[str]) -> str:
    score = stats["hunks"] + stats["only_in_entries"] + len(findings)
    if score >= 150:
        return "high"
    if score >= 40:
        return "medium"
    return "low"


def write_summary_md(report: Path, summary: dict) -> None:
    md = report / "summary.md"
    findings_preview = summary["suspicious_findings"][:15]
    preview = "\n".join(f"- `{line}`" for line in findings_preview) or "- none"
    md.write_text(
        "\n".join(
            [
                "# Audit Report",
                "",
                f"- Generated: {summary['generated_at']}",
                f"- Baseline: `{summary['baseline']}`",
                f"- Current: `{summary['current']}`",
                "",
                "## Executive summary",
                f"- Risk level: **{summary['risk_level']}**",
                f"- Files changed: **{summary['diff_stats']['files_changed']}**",
                f"- Diff hunks: **{summary['diff_stats']['hunks']}**",
                f"- Added lines: **{summary['diff_stats']['added_lines']}**",
                f"- Removed lines: **{summary['diff_stats']['removed_lines']}**",
                f"- Suspicious findings: **{len(summary['suspicious_findings'])}**",
                "",
                "## Suspicious findings (sample)",
                preview,
            ]
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--baseline", required=True)
    p.add_argument("--current", required=True)
    p.add_argument("--report", required=True)
    args = p.parse_args()

    baseline = Path(args.baseline).resolve()
    current = Path(args.current).resolve()
    report = Path(args.report).resolve()
    report.mkdir(parents=True, exist_ok=True)

    raw = run_diff(baseline, current)
    normalized = normalize_diff(raw)
    stats = diff_stats(normalized)
    findings = collect_suspicions(current)
    level = risk_level(stats, findings)

    (report / "diff_normalized.txt").write_text("\n".join(normalized) + "\n", encoding="utf-8")

    summary = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "baseline": str(baseline),
        "current": str(current),
        "risk_level": level,
        "diff_stats": stats,
        "suspicious_findings": findings,
    }

    (report / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    write_summary_md(report, summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
